#!/usr/bin/perl

##############################################################################
#
#		vpp -- verilog preprocessor		Ver.1.10
#		Copyright(C) by DDS
#
##############################################################################
#
#	2013.01.16	2��������θ��� [...] ��ȿ�����Ƥ��������ʤäƤ��Τ���
#	2013.01.17	$repeat �Υͥ��Ȥ��б�
#	2013.01.18	GetModuleIO() �� parameter �� wire �����ˤ���
#	2013.12.12	perlpp ��¢
#	2014.03.03	����ϥ֥�å��� #repeat ��������Ϥ��ʤ�
#				MultiLineParser, ReadSkelList ��� ExpandMacro �򤫤���
#	2014.04.10	instance �� parameter �ꥹ�Ȥǲ��ԤǤ���褦�ˤ���
#	2014.05.14	parameter �� enum ���� enum_p �ɲ�
#	2014.05.15	�ޥ����ɲ�
#	2014.08.29	/* */ ������Ȥ���ʾ�ʸ���󡦥����Ȳ��Ϥ򤷤ʤ��ä�
#	2014.09.21	module hoge #( param ... ) ( ... ) �������б�
#
##############################################################################

use strict 'vars';
use strict 'refs';

my $enum = 1;
my $ATTR_REF		= $enum;				# wire �����Ȥ��줿
my $ATTR_FIX		= ( $enum <<= 1 );		# wire �˽��Ϥ��줿
my $ATTR_BYDIR		= ( $enum <<= 1 );		# inout ����³���줿
my $ATTR_IN			= ( $enum <<= 1 );		# ���� I
my $ATTR_OUT		= ( $enum <<= 1 );		# ���� O
my $ATTR_INOUT		= ( $enum <<= 1 );		# ���� IO
my $ATTR_WIRE		= ( $enum <<= 1 );		# ���� W
my $ATTR_MD			= ( $enum <<= 1 );		# multiple drv ( �ٹ����� )
my $ATTR_DEF		= ( $enum <<= 1 );		# �ݡ��ȡ���������Ѥ�
my $ATTR_DC_WEAK_W	= ( $enum <<= 1 );		# Bus Size �ϼ��ο���ٹ������
my $ATTR_WEAK_W		= ( $enum <<= 1 );		# Bus Size �ϼ��ο���
my $ATTR_USED		= ( $enum <<= 1 );		# ���� template �����Ѥ��줿
my $ATTR_NC			= ~0;

$enum = 0;
my $BLKMODE_NORMAL	= $enum++;	# �֥�å���
my $BLKMODE_REPEAT	= $enum++;	# repeat �֥�å�
my $BLKMODE_PERL	= $enum++;	# perl �֥�å�
my $BLKMODE_IF		= $enum++;	# if �֥�å�
my $BLKMODE_ELSE	= $enum++;	# else �֥�å�

$enum = 1;
my $EX_CPP			= $enum;		# CPP �ޥ���Ÿ��
my $EX_REP			= $enum <<= 1;	# repeat �ޥ���Ÿ��
my $EX_INTFUNC		= $enum <<= 1;	# sizeof, typeof Ÿ��
my $EX_STR			= $enum <<= 1;	# ʸ�����ƥ��
my $EX_RMSTR		= $enum <<= 1;	# ʸ�����ƥ����
my $EX_COMMENT		= $enum <<= 1;	# ������
my $EX_RMCOMMENT	= $enum <<= 1;	# �����Ⱥ��
my $EX_NOREAD		= $enum <<= 1;	# $fpIn �����ɲ��ɤ߹��ߤ��ʤ�
my $EX_NOSIGINFO	= $enum <<= 1;	# %WireList �����Բ�

$enum = 1;
my $MODMODE_NONE	= 0;
my $MODMODE_NORMAL	= $enum;
my $MODMODE_TEST	= $enum <<= 1;
my $MODMODE_INC		= $enum <<= 1;
my $MODMODE_TESTINC	= $MODMODE_TEST | $MODMODE_INC;

my $CSymbol			= qr/\b[_a-zA-Z]\w*\b/;
my $CSymbol2		= qr/\b[_a-zA-Z\$]\w*\b/;
my $SigTypeDef		= qr/\b(?:parameter|wire|reg|input|output(?:\s+reg)?|inout)\b/;
my $DefSkelPort		= "(.*)";
my $DefSkelWire		= "\$1";

my $tab0 = 4 * 2;
my $tab1 = 4 * 7;
my $tab2 = 4 * 13;

my $ErrorCnt = 0;
my $TabWidth = 4;	# ������

my $TabWidthType	= 12;	# input / output ��
my $TabWidthBit		= 8;	# [xx:xx]

my $OpenClose;
   $OpenClose		= qr/\([^()]*(?:(??{$OpenClose})[^()]*)*\)/;
my $OpenCloseArg	= qr/[^(),]*(?:(??{$OpenClose})[^(),]*)*/;
my $Debug	= 0;

my $SEEK_SET = 0;

my( $DefFile, $RTLFile, $ListFile, $CppFile );
my $PrintBuf;
my $RTLBuf;
my $PerlBuf;
my $ModuleName;
my $ExpandTab;
my $BlockNoOutput	= 0;
my $BlockRepeat		= 0;
my( $fpIn, $fpOut, $fpList );

my $ResetLinePos	= 0;
my $VppStage		= 0;
my $bPrevLineBlank	= 1;
my $CppOnly			= 0;

# ����ơ��֥�ط�
my @WireList;
my %WireList;
my @SkelList;
my $iModuleMode;
my $PortDef;
my $ParamDef;
my %DefineTbl;

my( @CommentPool );

main();
exit( $ErrorCnt != 0 );

### main procedure ###########################################################

sub main{
	local( $_ );
	
	if( $#ARGV < 0 ){
		print( "usage: vpp.pl [-vE] [-I<path>] [-D<def>[=<val>]] [-tab<width>] <Def file>\n" );
		return;
	}
	
	# -DMACRO setup
	
	while( 1 ){
		$_ = $ARGV[ 0 ];
		
		if    ( /^-v/			){ $Debug = 1;
		}elsif( /^-I(.*)/		){ push( @INC, $1 );
		}elsif( /^-D(.+?)=(.+)/	){ AddCppMacro( $1, $2 );
		}elsif( /^-D(.+)/		){ AddCppMacro( $1 );
		}elsif( /^-E/			){ $CppOnly = 1;
		}elsif( /^-tab(.*)/		){ $ExpandTab = 1; $TabWidth = eval( $1 );
		}else					 { last;
		}
		shift( @ARGV );
	}
	
	# tab ��Ĵ��
	$tab0 = $TabWidth * 2;
	
	# set up default file name
	
	$DefFile  = $ARGV[ 0 ];
	
	$DefFile =~ /(.*?)(\.def)?(\.[^\.]+)$/;
	
	$RTLFile  = "$1$3";
	$RTLFile  = "$1_top$3" if( $RTLFile eq $DefFile );
	$ListFile = "$1.list";
	$CppFile  = "$1.cpp$3.$$";
	
	# �ǥե���ȥޥ���꡼��
	$fpIn		= DATA;
	$PrintBuf	= \$RTLBuf;
	$RTLBuf		= "";
	ExpandRepeatOutput();
	undef( $PrintBuf );
	undef( $RTLBuf );
	undef( $fpIn );
	
	# expand $repeat
	if( !open( $fpIn, "< $DefFile" )){
		Error( "can't open file \"$DefFile\"" );
		return;
	}
	
	open( $fpOut, "> $CppFile" );
	
	ExpandRepeatOutput();
	
	if( $Debug ){
		print( "=== macro ===\n" );
		foreach $_ ( sort keys %DefineTbl ){
			printf( "$_%s\t$DefineTbl{ $_ }{ macro }\n", $DefineTbl{ $_ }{ args } eq 's' ? '' : '()' );
		}
		print( "=== comment =\n" );
		print( join( "\n", @CommentPool ));
		print( "=============\n" );
	}
	undef( %DefineTbl );
	
	close( $fpOut );
	close( $fpIn );
	
	if( !open( $fpIn, "< $CppFile" )){
		Error( "can't open file \"$CppFile\"" );
		return;
	}
	
	if( $CppOnly ){
		while( <$fpIn> ){
			print( $Debug ? $_ : ExpandMacro( $_, $EX_STR | $EX_COMMENT ));
		}
	}else{
		# vpp
		
		unlink( $ListFile );
		
		$ExpandTab ?
			open( $fpOut, "| expand -$TabWidth > $RTLFile" ) :
			open( $fpOut, "> $RTLFile" );
		
		$VppStage = 1;
		MultiLineParser();
		
		close( $fpOut );
		close( $fpIn );
	}
	
	unlink( $CppFile );
}

### 1���ɤ� #################################################################

sub ReadLine {
	local $_ = ReadLineSub( $_[ 0 ] );
	
	my( $Cnt );
	my( $Line );
	my( $LineCnt ) = $.;
	
	while( m@(//#?|/\*|(?<!\\)")@ ){
		$Cnt = $#CommentPool + 1;
		
		if( $1 eq '//' ){
			push( @CommentPool, $1 ) if( s#(//.*)#<__COMMENT_${Cnt}__># && !$VppStage );
		}elsif( $1 eq '"' ){
			if( s/((?<!\\)".*?(?<!\\)")/<__STRING_${Cnt}__>/ ){
				push( @CommentPool, $1 ) if( !$VppStage );
			}else{
				Error( 'unterminated "' );
				s/"//;
			}
		}else{
			if( s#(/\*.*?\*/)#<__COMMENT_${Cnt}__>#s ){
				# /* ... */ ���Ȥ�ȯ�����줿�顤�ִ�
				push( @CommentPool, $1 ) if( !$VppStage );
				$ResetLinePos = $.;
			}
			# /* ... */ ���Ȥ�ȯ������ʤ��Τǡ�ȯ�������ޤǹ� cat
			if( !( $Line = ReadLineSub( $_[ 0 ] ))){
				Error( 'unterminated */', $LineCnt );
				last;
			}
			$_ .= $Line;
		}
	}
	
	$_;
}

sub ReadLineSub {
	my( $fp ) = @_;
	local( $_ );
	
	while( <$fp> ){
		if( $VppStage && /^#\s*(\d+)\s+"(.*)"/ ){
			$. = $1 - 1;
			$DefFile = ( $2 eq "-" ) ? $ARGV[ 0 ] : $2;
		}elsif( m@^\s*//#@ ){
			$ResetLinePos = $.;
			next;
		}else{
			s@\s*//#.*@@;
			last;
		}
	}
	$_;
}

# �ؿ��ޥ����Ѥ� ( ... ) �����
sub GetFuncArg {
	local $_;
	my $fp;
	( $fp, $_ ) = @_;
	my( $Line );
	
	while( !/^$OpenClose/ ){
		$ResetLinePos = $.;
		
		if( !( $Line = ReadLine( $fp ))){
			Error( "unmatched ')'" );
			last;
		}
		$_ .= $Line;
	}
	
	$_;
}

### Start of the module #####################################################

sub ExpandRepeatOutput {
	my( $BlockMode, $bNoOutput ) = @_;
	$BlockMode	= 0 if( !defined( $BlockMode ));
	$bNoOutput	= 0 if( !defined( $bNoOutput ));
	local( $_ );
	
	$BlockNoOutput	<<= 1;
	$BlockNoOutput	|= $bNoOutput;
	$BlockRepeat	<<= 1;
	$BlockRepeat	|= ( $BlockMode == $BLKMODE_REPEAT ? 1 : 0 );
	
	my $Line;
	my $i;
	my $BlockMode2;
	my $LineCnt = $.;
	
	while( $_ = ReadLine( $fpIn )){
		# ���ɽ���θߴ���
		s/\$(repeat|perl)/#$1/g;
		s/\$end\b/#endrep/g;
		s/\bEOF\b/#endperl/g;
		s/(?<!#)\benum\b/#enum/g;
		
		if( /^\s*#\s*(?:ifdef|ifndef|if|elif|else|endif|repeat|endrep|perl|endperl|enum|enum_p|define|define|define|undef|include|require)\b/ ){
			
			# \ �ǽ���äƤ���Ԥ�Ϣ��
			while( /\\$/ ){
				if( !( $Line = ReadLine( $fpIn ))){
					last;
				}
				$_ .= $Line;
			}
			
			$ResetLinePos = $.;
			
			# \ ���
			s/[\t ]*\\[\x0D\x0A]+[\t ]*/ /g;
			s/\s+$//g;
			s/^\s*#\s*//;
			
			$_ = ExpandMacro( $_, $EX_REP | $EX_RMCOMMENT );
			
			# $DefineTbl{ $1 }{ args }:  >=0: ����  <0: ���Ѱ���  's': ñ��ޥ���
			# $DefineTbl{ $1 }{ macro }:  �ޥ����������
			
			if( /^ifdef\b(.*)/ ){
				ExpandRepeatOutput( $BLKMODE_IF, !IfBlockEval( "defined $1" ));
			}elsif( /^ifndef\b(.*)/ ){
				ExpandRepeatOutput( $BLKMODE_IF,  IfBlockEval( "defined $1" ));
			}elsif( /^if\b(.*)/ ){
				ExpandRepeatOutput( $BLKMODE_IF, !IfBlockEval( $1 ));
			}elsif( /^elif\b(.*)/ ){
				if( $BlockMode != $BLKMODE_IF ){
					Error( "unexpected #elif" );
				}elsif( $bNoOutput ){
					# �ޤ����Ϥ��Ƥ��ʤ�
					$bNoOutput = !IfBlockEval( $1 );
					$BlockNoOutput &= ~1;
					$BlockNoOutput |= 1 if( $bNoOutput );
				}else{
					# �⤦���Ϥ���
					$BlockNoOutput |= 1;
				}
			}elsif( /^else\b/ ){
				# else
				if( $BlockMode != $BLKMODE_IF ){
					Error( "unexpected #else" );
				}elsif( $bNoOutput ){
					# �ޤ����Ϥ��Ƥ��ʤ�
					$bNoOutput = 0;
					$BlockNoOutput &= ~1;
				}else{
					# �⤦���Ϥ���
					$BlockNoOutput |= 1;
				}
			}elsif( /^endif\b/ ){
				# endif
				if(
					$BlockMode != $BLKMODE_IF &&
					$BlockMode != $BLKMODE_ELSE
				){
					Error( "unexpected #endif" );
				}else{
					last;
				}
			}elsif( /^repeat\s*($OpenClose)/ ){
				# repeat / endrepeat
				RepeatOutput( $BlockMode, $1 );
			}elsif( /^endrep\b/ ){
				if( $BlockMode != $BLKMODE_REPEAT ){
					Error( "unexpected #endrep" );
				}else{
					last;
				}
			}elsif( /^perl\b/s ){
				# perl / endperl
				ExecPerl();
			}elsif( /^endperl\b/ ){
				if( $BlockMode != $BLKMODE_PERL ){
					Error( "unexpected #endperl" );
				}else{
					last;
				}
			}elsif( /^enum\b(.*)/ ){
				Enumerate( $1, 0 );
			}elsif( /^enum_p\b(.*)/ ){
				Enumerate( $1, 1 );
			}elsif( !$BlockNoOutput ){
				if( /^define\s+($CSymbol)$/ ){
					# ̾���������
					AddCppMacro( $1 );
				}elsif( /^define\s+($CSymbol)\s+(.+)/ ){
					# ̾���������
					AddCppMacro( $1, $2 );
				}elsif( /^define\s+($CSymbol)($OpenClose)\s*(.*)/ ){
					# �ؿ��ޥ���
					my( $Name, $ArgList, $Macro ) = ( $1, $2, $3 );
					
					# ArgList ������ʬ��
					$ArgList =~ s/^\(\s*//;
					$ArgList =~ s/\s*\)$//;
					my( @ArgList ) = split( /\s*,\s*/, $ArgList );
					
					# �ޥ�����ΰ������ü�ʸ�����ִ�
					my $ArgNum = $#ArgList + 1;
					
					for( $i = 0; $i <= $#ArgList; ++$i ){
						if( $i == $#ArgList && $ArgList[ $i ] eq '...' ){
							$ArgNum = -$ArgNum;
							last;
						}
						$Macro =~ s/\b$ArgList[ $i ]\b/<__\ARG_${i}\__>/g;
					}
					
					AddCppMacro( $Name, $Macro, $ArgNum );
				}elsif( /^undef\s+($CSymbol)$/ ){
					# undef
					delete( $DefineTbl{ $1 } );
				}elsif( /^include\s*(.*)/ ){
					Include( $1 );
				}elsif( /^require\s+(.*)/ ){
					Require( $1 );
				}elsif( !$BlockNoOutput ){
					PrintRTL( ExpandMacro( $_, $EX_CPP | $EX_REP ));
				}
			}
		}elsif( !$BlockNoOutput ){
			PrintRTL( ExpandMacro( $_, $EX_CPP | $EX_REP ));
		}
	}
	
	if( $_ eq '' && $BlockMode != $BLKMODE_NORMAL ){
		if(     $BlockMode == $BLKMODE_REPEAT	){ Error( "unterminated #repeat",	$LineCnt );
		}elsif( $BlockMode == $BLKMODE_PERL		){ Error( "unterminated #perl",		$LineCnt );
		}elsif( $BlockMode == $BLKMODE_IF		){ Error( "unterminated #if",		$LineCnt );
		}elsif( $BlockMode == $BLKMODE_ELSE		){ Error( "unterminated #else",		$LineCnt );
		}
	}
	
	$BlockNoOutput	>>= 1;
	$BlockRepeat	>>= 1;
}

### �ޥ���饤��ѡ��� #######################################################

sub MultiLineParser {
	local( $_ );
	my( $Line, $Word );
	
	while( $_ = ReadLine( $fpIn )){
		( $Word, $Line ) = GetWord(
			ExpandMacro( $_, $EX_INTFUNC | $EX_STR | $EX_RMCOMMENT )
		);
		
		if    ( $Word eq 'module'			){ StartModule( $Line );
		}elsif( $Word eq 'module_inc'		){ StartModule( $Line, $MODMODE_INC );
		}elsif( $Word eq 'testmodule'		){ StartModule( $Line, $MODMODE_TEST );
		}elsif( $Word eq 'testmodule_inc'	){ StartModule( $Line, $MODMODE_TESTINC );
		}elsif( $Word eq 'endmodule'		){ EndModule( $_ );
		}elsif( $Word eq 'instance'			){ DefineInst( $Line );
		}elsif( $Word eq '$wire'			){ DefineDefWireSkel( $Line );
		}elsif( $Word eq '$header'			){ OutputHeader();
		}elsif( $Word eq '$AllInputs'		){ PrintAllInputs( $Line, $_ );
		}else{
			if( $Word eq '_module' || $Word eq '_endmodule' ){
				$_ =~ s/\b_((?:end)?module)\b/$1/;
			}
			PrintRTL( ExpandMacro( $_, $EX_INTFUNC | $EX_STR | $EX_COMMENT ));
		}
	}
}

### Start of the module #####################################################

sub StartModule{
	local( $_ );
	( $_, $iModuleMode ) = @_;
	
	my(
		@ModuleIO,
		@IOList,
		$InOut,
		$BitWidth,
		$Attr,
		$Port,
		$Line
	);
	
	# wire list �����
	
	@WireList	= ();
	%WireList	= ();
	$iModuleMode	= $MODMODE_NORMAL if( !defined( $iModuleMode ));
	$PortDef		= '';
	$ParamDef		= '';
	
	$PrintBuf	= \$RTLBuf;
	$RTLBuf		= "";
	
	( $ModuleName, $_ ) = GetWord( ExpandMacro( $_, $EX_INTFUNC | $EX_RMCOMMENT | $EX_NOREAD ));
	
	#PrintRTL( SkipToSemiColon( $_ ));
	#SkipToSemiColon( $_ );
	
	# module hoge #( ... ) ������ parameter ǧ��
	if( /^(\s*#)(\(.*)/ ){
		( $ParamDef, $_ ) = ( $1, "($'\n" );
		while( !/^$OpenClose/ ){
			$Line = ReadLine( $fpIn );
			last if( $Line eq '' );
			$_ .= ExpandMacro( $Line, $EX_INTFUNC );
		}
		
		/^($OpenClose\s*)/;
		$ParamDef .= $1;
		$_ = $';
	}
	
	# ); �ޤ��ɤ� �����ɤ᤿�餽���ݡ��ȥꥹ�ȤȤߤʤ�
	
	if( !/^\s*;/ ){
		while( $_ = ReadLine( $fpIn )){
			$_ = ExpandMacro( $_, $EX_INTFUNC );
			
			last if( /\s*\);/ );
			next if( /^\s*\(\s*$/ || /^#/ );
			
			s/\boutput\s*reg\b/output reg/;
			s/outreg/output reg/g;
			
			if( /^\s*($SigTypeDef)\s*(\[[^\]]+\])?\s*(.*)/ ){
				if( !defined( $2 )){
					$_ = "\t" .
						TabSpace( $1, $TabWidthType, $TabWidth ) .
						TabSpace( '', $TabWidthBit,  $TabWidth ) .
						$3 . "\n";
				}else{
					$_ = "\t" .
						TabSpace( $1, $TabWidthType, $TabWidth ) .
						TabSpace( $2, $TabWidthBit,  $TabWidth ) .
						$3 . "\n";
				}
			}else{
				s|^[ \t]*|\t|;
			}
			$PortDef .= $_;
		}
		
		if( $PortDef =~ /$SigTypeDef/ ){
			$PortDef =~ s/;([^;]*)$/$1/;
			$PortDef =~ s/;/,/g;
			$PortDef = ExpandMacro( $PortDef, $EX_STR | $EX_COMMENT | $EX_NOREAD );
		}else{
			$PortDef = '';
		}
	}
	
	# �� module �� wire / port �ꥹ�Ȥ�get
	
	@ModuleIO = GetModuleIO( $ModuleName, $CppFile, $ARGV[ 0 ] );
	
	# input/output ʸ 1 �Ԥ��Ȥν���
	
	while( $_ = shift( @ModuleIO )){
		
		( $InOut, $BitWidth, @IOList )	= split( /\t/, $_ );
		
		while( $Port = shift( @IOList )){
			
			$Attr = $InOut eq "input"	? $ATTR_DEF | $ATTR_IN		:
					$InOut eq "output"	? $ATTR_DEF | $ATTR_OUT		:
					$InOut eq "inout"	? $ATTR_DEF | $ATTR_INOUT	:
					$InOut eq "wire"	? $ATTR_DEF | $ATTR_WIRE	:
					$InOut eq "reg"		? $ATTR_DEF | $ATTR_WIRE | $ATTR_REF	:
					$InOut eq "assign"	? $ATTR_FIX | $ATTR_WEAK_W	: 0;
			
			if( $BitWidth eq '?' ){
				$Attr |= $ATTR_WEAK_W;
			}
			
			RegisterWire( $Port, $BitWidth, $Attr, $ModuleName );
		}
	}
}

### End of the module ########################################################

sub EndModule{
	local( $_ ) = @_;
	my(
		$Type,
		$bFirst,
		$Wire
	);
	
	my( $MSB, $LSB, $MSB_Drv, $LSB_Drv );
	
	# expand bus
	
	ExpandBus();
	
	PrintRTL( '//' ) if( $iModuleMode & $MODMODE_INC );
	PrintRTL( $_ );
	undef( $PrintBuf );
	
	# module port �ꥹ�Ȥ����
	
	$bFirst = 1;
	PrintRTL( '//' ) if( $iModuleMode & $MODMODE_INC );
	PrintRTL( "module $ModuleName" );
	
	if( $iModuleMode == $MODMODE_NORMAL ){
		
		my( $PortDef2 ) = '';
		
		foreach $Wire ( @WireList ){
			$Type = QueryWireType( $Wire, 'd' );
			
			if( $Type eq "input" || $Type eq "output" || $Type eq "inout" ){
				$PortDef2 .= FormatSigDef( $Type, $Wire->{ width }, $Wire->{ name }, ',' );
			}
		}
		
		if( $PortDef || $PortDef2 ){
			$PortDef .= "\t,\n" if( $PortDef && $PortDef2 );
			$PortDef2 =~ s/,([^,]*)$/$1/;
			PrintRTL( "$ParamDef(\n$PortDef$PortDef2)" );
		}
	}
	
	PrintRTL( ";\n" );
	
	# in/out/reg/wire �������
	
	foreach $Wire ( @WireList ){
		if(( $Type = QueryWireType( $Wire, "d" )) ne "" ){
			
			if( $iModuleMode & $MODMODE_NORMAL ){
				next if( $Type eq "input" || $Type eq "output" || $Type eq "inout" );
			}elsif( $iModuleMode & $MODMODE_TEST ){
				$Type = "reg"  if( $Type eq "input" );
				$Type = "wire" if( $Type eq "output" || $Type eq "inout" );
			}elsif( $iModuleMode & $MODMODE_INC ){
				# ��ƥ��ȥ⥸�塼��� include �⡼�ɤǤϡ��Ȥꤢ�������� wire �ˤ���
				$Type = 'wire';
			}
			
			PrintRTL( FormatSigDef( $Type, $Wire->{ width }, $Wire->{ name }, ';' ));
		}
	}
	
	# buf �ˤ���Ƥ������Ҥ�ե�å���
	
	print( $fpOut $RTLBuf );
	$RTLBuf = "";
	
	# wire �ꥹ�Ȥ���� for debug
	OutputWireList();
	
	$iModuleMode = $MODMODE_NONE;
}

sub FormatSigDef {
	local $_;
	my( $Type, $Width, $Name, $eol ) = @_;
	
	$_ = "\t" . TabSpace( $Type, $TabWidthType, $TabWidth );
	
	if( $Width eq "" || $Width =~ /^\[/ ){
		# bit ����ʤ� or [xx:xx]
		$_ .= TabSpace( $Width, $TabWidthBit, $TabWidth );
	}else{
		# 10:2 �Ȥ�
		$_ .= TabSpace( FormatBusWidth( $Width ), $TabWidthBit, $TabWidth );
	}
	
	$_ .= "$Name$eol\n";
}

### Evaluate #################################################################

sub Evaluate {
	local( $_ ) = @_;
	
	s/\$Eval\b//g;
	$_ = eval( $_ );
	Error( $@ ) if( $@ ne '' );
	return( $_ );
}

sub Evaluate2 {
	local( $_ ) = @_;
	local( @_ );
	
	s/\$Eval\b//g;
	@_ = eval( $_ );
	Error( $@ ) if( $@ ne '' );
	return( @_ );
}

### output normal line #######################################################

sub PrintRTL{
	local( $_ ) = @_;
	my( $tmp );
	
	# Case / FullCase ����
	s|\bC(asex?\s*\(.*\))|c$1 /* synopsys parallel_case */|g;
	s|\bFullC(asex?\s*\(.*\))|c$1 /* synopsys parallel_case full_case */|g;
	
	if( $VppStage ){
		# ���԰���
		s/^([ \t]*\n)([ \t]*\n)+/$1/gm;
	}else{
		if( $ResetLinePos ){
			if( $ResetLinePos == $. ){
				$_ .= sprintf( "# %d \"$DefFile\"\n", $. );
			}else{
				$_ = sprintf( "# %d \"$DefFile\"\n", $. ) . $_;
			}
			$ResetLinePos = 0;
		}
	}
	
	if( !( $VppStage && $bPrevLineBlank && /^\s*$/ )){
		if( defined( $PrintBuf )){
			$$PrintBuf .= $_;
		}else{
			print( $fpOut $_ );
		}
	}
	
	$bPrevLineBlank = /^\s*$/ if( $VppStage );
}

### read instance definition #################################################
# syntax:
#	instance <module name> [#(<params>)] <instance name> <module file> (
#		<port>	<wire>	<attr>
#		a(\d+)	aa[$1]			// �Х���«��
#		b		bb$n			// �Х�Ÿ����
#	);
#
#	���ȥ�ӥ塼��: <������><�ݡ��ȥ�����>
#	  ������:
#		M		Multiple drive �ٹ����������
#		B		bit width weakly defined �ٹ����������
#		U		tmpl isn't used �ٹ����������
#	  �ݡ��ȥ�����:
#		NP		reg/wire ������ʤ�
#		NC		Wire ��³���ʤ�
#		W		�ݡ��ȥ����פ���Ū�� wire �ˤ���
#		I		�ݡ��ȥ����פ���Ū�� input �ˤ���
#		O		�ݡ��ȥ����פ���Ū�� output �ˤ���
#		IO		�ݡ��ȥ����פ���Ū�� inout �ˤ���

sub DefineInst{
	local( $_ ) = @_;
	my(
		$Port,
		$Wire,
		$WireBus,
		$Attr,
		
		@ModuleIO,
		@IOList,
		$InOut,
		$BitWidth,
		$BitWidthWire,
		
		$bFirst,
		$Len,
		
		$tmp,
		$tmp2
	);
	
	@SkelList = ();
	
	my( $LineNo ) = $.;
	
	if( /#\(/ && !/#$OpenClose/ ){
		/^(.*?#)(.*)/;
		$tmp = $1;
		$_ = $tmp . GetFuncArg( $fpIn, $2 . "\n" );
	}
	
	if( !/\s+([\w\d]+)(\s+#\([^\)]+\))?\s+(\S+)\s+"?(\S+)"?\s*([\(;])/s ){
		Error( "syntax error (instance)" );
		return;
	}
	
	# get module name, module inst name, module file
	
	my( $ModuleName, $ModuleParam, $ModuleInst, $ModuleFile ) = ( $1, ExpandMacro( $2, $EX_STR | $EX_COMMENT ), $3, $4 );
	$ModuleParam = '' if( !defined( $ModuleParam ));
	
	if( $ModuleInst eq "*" ){
		$ModuleInst = $ModuleName;
	}
	
	if( $ModuleFile eq "*" ){
		$ModuleFile = $CppFile;
	}
	
	# read port->wire tmpl list
	
	ReadSkelList() if( $5 eq "(" );
	
	# instance �� header �����
	
	PrintRTL( "\t$ModuleName$ModuleParam $ModuleInst" );
	$bFirst = 1;
	
	# get sub module's port list
	
	@ModuleIO = GetModuleIO( $ModuleName, $ModuleFile );
	
	# input/output ʸ 1 �Ԥ��Ȥν���
	
	while( $_ = shift( @ModuleIO )){
		
		( $InOut, $BitWidth, @IOList )	= split( /\t/, $_ );
		next if( $InOut !~ /^(?:input|output|inout)$/ );
		
		while( $Port = shift( @IOList )){
			( $Wire, $Attr ) = ConvPort2Wire( $Port, $BitWidth );
			
			if( $Attr != $ATTR_NC ){
				
				# hoge(\d) --> hoge[$1] �к�
				
				$WireBus = $Wire;
				if( $WireBus  =~ /(.*)\[(\d+(?::\d+)?)\]$/ ){
					
					$WireBus		= $1;
					$BitWidthWire	= $2;
					$BitWidthWire	= $BitWidthWire =~ /^\d+$/ ? "$BitWidthWire:$BitWidthWire" : $BitWidthWire;
					
					# instance �� tmpl �����
					#  hoge  hoge[1] �ʤɤΤ褦�� wire ¦�� bit ���꤬
					# �Ĥ����Ȥ� wire �μºݤΥ��������狼��ʤ�����
					# ATTR_WEAK_W °����Ĥ���
					$Attr |= $ATTR_WEAK_W;
				}else{
					$BitWidthWire	= $BitWidth;
					
					# BusSize �� [BIT_DMEMADR-1:0] �ʤɤΤ褦�������ξ��
					# ���ΤȤ��� $ATTR_WEAK_W °����Ĥ���
					if( $BitWidth ne '' && $BitWidth !~ /^\d+:\d+$/ ){
						$Attr |= $ATTR_WEAK_W;
					}
				}
				
				# wire list ����Ͽ
				
				if( $Wire !~ /^\d/ ){
					$Attr |= ( $InOut eq "input" )	? $ATTR_REF		:
							 ( $InOut eq "output" )	? $ATTR_FIX		:
													  $ATTR_BYDIR	;
					
					# wire ̾����
					
					$WireBus =~ s/\d+'[hdob]\d+//g;
					$WireBus =~ s/[\s{}]//g;
					$WireBus =~ s/\b\d+\b//g;
					
					@_ = split( /,+/, $WireBus );
					
					if( $#_ > 0 ){
						# { ... , ... } ����concat ���椬��³����Ƥ���
						
						foreach $WireBus ( @_ ){
							RegisterWire(
								$WireBus,
								'?',
								$Attr |= $ATTR_WEAK_W,
								$ModuleName
							);
						}
					}else{
						RegisterWire(
							$WireBus,
							$BitWidthWire,
							$Attr,
							$ModuleName
						) if( $WireBus ne '' );
					}
				}elsif( $Wire =~ /^\d+$/ ){
					# �������������ꤵ�줿��硤bit��ɽ����Ĥ���
					$Wire = sprintf( "%d'd$Wire", GetBusWidth2( $BitWidth ));
				}
			}else{
				# NC ����
				$Wire = '';
			}
			
			# .hoge( hoge ), �� list �����
			
			PrintRTL( $bFirst ? "(\n" : ",\n" );
			$bFirst = 0;
			
			$tmp  = "\t" x (( $tab0 + $TabWidth - 1 ) / $TabWidth );
			$Len  = $tab0;
			
			$Wire =~ s/\$n//g;		#z $n �κ��
			$tmp .= ".$Port";
			$Len += length( $Port ) + 1;
			$tmp .= "\t" x (( $tab1 - $Len + $TabWidth - 1 ) / $TabWidth );
			$Len  = $tab1;
			
			$tmp .= "( $Wire";
			$Len += length( $Wire ) + 2;
			
			$tmp .= "\t" x (( $tab2 - $Len + $TabWidth - 1 ) / $TabWidth );
			$Len  = $tab2;
			
			$tmp .= ")";
			
			PrintRTL( "$tmp" );
		}
	}
	
	# instance �� footer �����
	
	PrintRTL( "\n\t)" ) if( !$bFirst );
	PrintRTL( ";\n" );
	
	# SkelList ̤���ѷٹ�
	
	WarnUnusedSkelList( $ModuleInst, $LineNo );
}

### search module & get IO definition ########################################

sub GetModuleIO{
	
	local $_;
	my( $ModuleName, $ModuleFile, $ModuleFileDisp ) = @_;
	my( $Buf, $bFound, $fp );
	
	$ModuleFileDisp = $ModuleFile if( !defined( $ModuleFileDisp ));
	
	$bFound = 0;
	
	if( !open( $fp, "< $ModuleFile" )){
		Error( "can't open file \"$ModuleFile\"" );
		return( "" );
	}
	
	# module ����Ƭ��õ��
	
	while( $_ = ReadLine( $fp )){
		if( $bFound ){
			# module ������
			last if( /\bendmodule\b/ );
			$Buf .= ExpandMacro( $_, $EX_INTFUNC | $EX_RMSTR | $EX_RMCOMMENT | $EX_NOSIGINFO );
		}else{
			# module ��ޤ����Ĥ��Ƥ��ʤ�
			if( /\b(?:test)?module(?:_inc)?\s+(.+)/ ){
				$_ = ExpandMacro( $1, $EX_INTFUNC | $EX_NOREAD | $EX_NOSIGINFO );
				$bFound = 1 if( /^$ModuleName\b/ );
			}
		}
	}
	
	close( $fp );
	
	if( !$bFound ){
		Error( "can't find module \"$ModuleName\@$ModuleFile\"" );
		return( "" );
	}
	
	$_ = $Buf;
	
	# delete comment
	s/\btask\b.*?\bendtask\b//gs;
	s/\bfunction\b.*?\bendfunction\b//gs;
	s/^\s*`.*//g;
	
	# delete \n
	s/[\x0D\x0A\t ]+/ /g;
	
	# split
	#print if( $Debug );
	s/\boutreg\b/output reg/g;
	s/($SigTypeDef)/\n$1/g;
	s/ *[;\)].*//g;
	
	# port �ʳ�����
	s/(.*)/DeleteExceptPort($1)/ge;
	s/ *\n+/\n/g;
	s/^\n//g;
	s/\n$//g;
	#print( "$ModuleName--------\n$_\n" ); # if( $Debug );
	
	return( split( /\n/, $_ ));
}

sub DeleteExceptPort{
	local( $_ ) = @_;
	my( $tmp );
	
	s/\boutput\s+reg/output/g;
	
	if( /^($SigTypeDef)\s*/ ){
		
		my( $Type ) = $1 eq 'parameter' ? 'wire' : $1;
		my( $Width ) = '';
		
		$_ = $';
		
		# �Х��������λ��� [?] �Ȥ�����Τ���
		if( /^\[(.+?)\]\s*/ ){
			( $_, $tmp ) = ( $1, $' );
			
			s/^\s+//;
			s/\s+$//;
			s/\s+/ /g;
			s/\s*:\s*/:/;
			
			( $Width, $_ ) = ( $_, $tmp );
		}
		
		s/\[.*?\]//g;	# 2��������θ������� [...] ����
		s/\s*=.*//g;	# wire hoge = hoge �� = �ʹߤ���
		
		s/[\s:,]+$//;
		s/[ ;,]+/\t/g;
		
		$_ = "$Type\t$Width\t$_";
		
	}elsif( /^assign\b/ ){
		# assign �Υ磻�䡼�ϡ�= ľ���μ��̻Ҥ����
		s/\s*=.*//g;
		/\s($CSymbol)$/;
		$_ = "assign\t?\t$1";
	}else{
		$_ = '';
	}
	
	return( $_ );
}

### get word #################################################################

sub GetWord{
	local( $_ ) = @_;
	
	s/\/\/.*//g;	# remove comment
	
	return( $1, $2 ) if( /^\s*([\w\d\$]+)(.*)/ || /^\s*(.)(.*)/ );
	return ( '', $_ );
}

### print error msg ##########################################################

sub Error{
	local $_;
	my $LineNo;
	( $_, $LineNo ) = @_;
	printf( "$DefFile(%d): $_\n", $LineNo || $. );
	++$ErrorCnt;
}

sub Warning{
	local $_;
	my $LineNo;
	( $_, $LineNo ) = @_;
	printf( "$DefFile(%d): Warning: $_\n", $LineNo || $. );
}

### define default port --> wire name ########################################

sub DefineDefWireSkel{
	local( $_ ) = @_;
	
	if( /\s*(\S+)\s+(\S+)/ ){
		$DefSkelPort = $1;
		$DefSkelWire = $2;
	}else{
		Error( "syntax error (template)" );
	}
}

### output header ############################################################

sub OutputHeader{
	
	my( $sec, $min, $hour, $mday, $mon, $year ) = localtime( time );
	my( $DateStr ) =
		sprintf( "%d/%02d/%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );
	
	local $_ = $DefFile;
	s/\..*//g;
	
	print( $fpOut <<EOF );
/*****************************************************************************

	$RTLFile -- $_ module	generated by vpp.pl
	
	Date     : $DateStr
	Def file : $DefFile

*****************************************************************************/
EOF
}

### skip to semi colon #######################################################

sub SkipToSemiColon{
	
	local( $_ ) = @_;
	
	do{
		goto ExitLoop if( s/.*?;//g );
	}while( $_ = ReadLine( $fpIn ));
	
  ExitLoop:
	return( $_ );
}

### read port/wire tmpl list #################################################

sub ReadSkelList{
	
	local $_;
	my(
		$Port,
		$Wire,
		$Attr,
		$AttrLetter
	);
	
	while( $_ = ReadLine( $fpIn )){
		$_ = ExpandMacro( $_, $EX_INTFUNC | $EX_STR | $EX_RMCOMMENT );
		s/\/\/.*//;
		s/#.*//;
		next if( /^\s*$/ );
		last if( /^\s*\);/ );
		
		/^\s*(\S+)\s*(\S*)\s*(\S*)/;
		
		( $Port, $Wire, $AttrLetter ) = ( $1, $2, $3 );
		
		if( $Wire =~ /^[MBU]?(?:NP|NC|W|I|O|IO|U)$/ ){
			$AttrLetter = $Wire;
			$Wire = "";
		}
		
		# attr
		
		$Attr = 0;
		
		$Attr |= $ATTR_MD			if( $AttrLetter =~ /M/ );
		$Attr |= $ATTR_DC_WEAK_W	if( $AttrLetter =~ /B/ );
		$Attr |= $ATTR_USED			if( $AttrLetter =~ /U/ );
		$Attr |=
			( $AttrLetter =~ /NP$/ ) ? $ATTR_DEF	:
			( $AttrLetter =~ /NC$/ ) ? $ATTR_NC		:
			( $AttrLetter =~ /W$/  ) ? $ATTR_WIRE	:
			( $AttrLetter =~ /I$/  ) ? $ATTR_IN		:
			( $AttrLetter =~ /O$/  ) ? $ATTR_OUT	:
			( $AttrLetter =~ /IO$/ ) ? $ATTR_INOUT	:
								0;
		
		push( @SkelList, {
			'port'	=> $Port,
			'wire'	=> $Wire,
			'attr'	=> $Attr,
		} );
	}
}

### tmpl list ̤���ѷٹ� #####################################################

sub WarnUnusedSkelList{
	
	my( $LineNo );
	local( $_ );
	( $_, $LineNo ) = @_;
	my( $Skel );
	
	foreach $Skel ( @SkelList ){
		if( !( $Skel->{ attr } && $ATTR_USED )){
			Warning( "unused template ( $Skel->{ port } --> $Skel->{ wire } \@ $_ )", $LineNo );
		}
	}
}

### convert port name to wire name ###########################################

sub ConvPort2Wire {
	
	my( $Port, $BitWidth ) = @_;
	my(
		$SkelPort,
		$SkelWire,
		
		$Wire,
		$Attr,
		
		$Skel
	);
	
	$SkelPort = $DefSkelPort;
	$SkelWire = $DefSkelWire;
	$Attr	  = 0;
	
	foreach $Skel ( @SkelList ){
		# bit���� 0 �ʤΤ� SkelWire �� $n �����ä��顤
		# ����Ū�� hit �����ʤ�
		next if( $BitWidth eq '' && $Skel->{ wire } =~ /\$n/ );
		
		# Hit ����
		if( $Port =~ /^$Skel->{ port }$/ ){
			# port tmpl ���Ѥ��줿
			$Skel->{ attr } |= $ATTR_USED;
			
			$SkelPort = $Skel->{ port };
			$SkelWire = $Skel->{ wire };
			$Attr	  = $Skel->{ attr };
			
			# NC �ʤ�ꥹ�Ȥ���ʤ�
			
			if( $Attr == $ATTR_NC ){
				return( "", $Attr );
			}
			last;
		}
	}
	
	# $<n> ���ִ�
	if( $SkelWire eq "" ){
		$SkelPort = $DefSkelPort;
		$SkelWire = $DefSkelWire;
	}
	
	$Wire =  $SkelWire;
	$Port =~ /^$SkelPort$/;
	
	my( $tmp1, $tmp2, $tmp3, $tmp4 ) = ( $1, $2, $3, $4 );
	
	$Wire =~ s/\$1/$tmp1/g;
	$Wire =~ s/\$2/$tmp2/g;
	$Wire =~ s/\$3/$tmp3/g;
	$Wire =~ s/\$4/$tmp4/g;
	
	return( $Wire, $Attr );
}

### wire ����Ͽ ##############################################################

sub RegisterWire{
	
	my( $Name, $BitWidth, $Attr, $ModuleName ) = @_;
	my( $Wire );
	
	my( $MSB0, $MSB1, $LSB0, $LSB1 );
	
	if( defined( $Wire = $WireList{ $Name } )){
		# ���Ǥ���Ͽ�Ѥ�
		
		# ATTR_WEAK_W �������� BitWidth �򹹿�����
		if(
			!( $Attr			& $ATTR_WEAK_W ) &&
			( $Wire->{ attr }	& $ATTR_WEAK_W )
		){
			# List �� Weak �ǡ��������Τ� Hard �ʤΤ�����
			$Wire->{ width } = $BitWidth;
			
			# list �� ATTR_WEAK_W °����ä�
			$Wire->{ attr } &= ~$ATTR_WEAK_W;
			
		}elsif(
			( $Attr				& $ATTR_WEAK_W ) &&
			( $Wire->{ attr }	& $ATTR_WEAK_W ) &&
			$Wire->{ width } =~ /^\d+:\d+$/ && $BitWidth =~ /^\d+:\d+$/
		){
			# List���������� �Ȥ�� Weak �ʤΤǡ��礭���ۤ���Ȥ�
			
			( $MSB0, $LSB0 ) = GetBusWidth( $Wire->{ width } );
			( $MSB1, $LSB1 ) = GetBusWidth( $BitWidth );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$Wire->{ width } = $BitWidth = "$MSB0:$LSB0";
			
		}elsif(
			!( $Attr			& $ATTR_WEAK_W ) &&
			!( $Wire->{ attr }	& $ATTR_WEAK_W ) &&
			$Wire->{ width } =~ /^\d+:\d+$/ && $BitWidth =~ /^\d+:\d+$/
		){
			# ξ�� Hard �ʤΤǡ�����������äƤ���� size mismatch �ٹ�
			
			if( GetBusWidth2( $Wire->{ width } ) != GetBusWidth2( $BitWidth )){
				Warning( "unmatch port width ( $ModuleName.$Name $BitWidth != $Wire->{ width } )" );
			}
		}
		
		# ξ�� inout ���ʤ顤��Ͽ����ۤ��� REF ���ѹ�
		
		if( $Wire->{ attr } & $Attr & $ATTR_INOUT ){
			$Attr |= $ATTR_REF;
		}
		
		# multiple driver �ٹ�
		
		if(
			( $Wire->{ attr } & $Attr & $ATTR_FIX ) &&
			!( $Attr & $ATTR_MD )
		){
			Warning( "multiple driver ( wire : $Name )" );
		}
		
		$Wire->{ attr } |= ( $Attr & ~$ATTR_WEAK_W );
		
	}else{
		# ������Ͽ
		
		push( @WireList, $Wire = {
			'name'	=> $Name,
			'width'	=> $BitWidth,
			'attr'	=> $Attr
		} );
		
		$WireList{ $Name } = $Wire;
	}
}

### query wire type & returns "in/out/inout" #################################
# $Mode eq "d" �� in/out/wire ���ʸ�⡼��

sub QueryWireType{
	
	my( $Wire, $Mode ) = @_;
	my( $Attr ) = $Wire->{ attr };
	
	return( ''		 ) if( $Attr & $ATTR_DEF  && $Mode eq 'd' );
	return( 'input'	 ) if( $Attr & $ATTR_IN );
	return( 'output' ) if( $Attr & $ATTR_OUT );
	return( 'inout'	 ) if( $Attr & $ATTR_INOUT );
	return( 'wire'	 ) if( $Attr & $ATTR_WIRE );
	return( 'inout'	 ) if(( $Attr & ( $ATTR_BYDIR | $ATTR_REF | $ATTR_FIX )) == $ATTR_BYDIR );
	return( 'input'	 ) if(( $Attr & ( $ATTR_REF | $ATTR_FIX )) == $ATTR_REF );
	return( 'output' ) if(( $Attr & ( $ATTR_REF | $ATTR_FIX )) == $ATTR_FIX );
	return( 'wire'	 ) if(( $Attr & ( $ATTR_REF | $ATTR_FIX )) == ( $ATTR_REF | $ATTR_FIX ));
	
	return( '' );
}

### output wire list #########################################################

sub OutputWireList{
	
	my(
		@WireListBuf,
		
		$WireCntUnresolved,
		$WireCntAdded,
		$Attr,
		$Type,
		$Wire,
	);
	
	$WireCntUnresolved = 0;
	$WireCntAdded	   = 0;
	
	foreach $Wire ( @WireList ){
		
		$Attr = $Wire->{ attr };
		$Type = QueryWireType( $Wire, "" );
		
		$Type =	( $Type eq "input" )	? "I" :
				( $Type eq "output" )	? "O" :
				( $Type eq "inout" )	? "B" :
				( $Type eq "wire" )		? "W" :
										  "-" ;
		
		++$WireCntUnresolved if( !( $Attr & ( $ATTR_BYDIR | $ATTR_FIX | $ATTR_REF )));
		if( !( $Attr & $ATTR_DEF ) && ( $Type =~ /[IOB]/ )){
			++$WireCntAdded;
			Warning( "'$ModuleName.$Wire->{ name }' is undefined, generated automatically" )
				if( !( $iModuleMode & $MODMODE_TEST ));
		}
		
		push( @WireListBuf, (
			$Type .
			(( $Attr & $ATTR_DEF )		? "d" :
			 ( $Type =~ /[IOB]/ )		? "!" : "-" ) .
			(( $Attr & ( $ATTR_BYDIR | $ATTR_FIX | $ATTR_REF ))
										? "-" : "!" ) .
			(( $Attr & $ATTR_WIRE )		? "W" :
			 ( $Attr & $ATTR_INOUT )	? "B" :
			 ( $Attr & $ATTR_OUT )		? "O" :
			 ( $Attr & $ATTR_IN )		? "I" : "-" ) .
			(( $Attr & $ATTR_BYDIR )	? "B" : "-" ) .
			(( $Attr & $ATTR_FIX )		? "F" : "-" ) .
			(( $Attr & $ATTR_REF )		? "R" : "-" ) .
			"\t$Wire->{ width }\t$Wire->{ name }\n"
		));
		
		# bus width is weakly defined error
		#Warning( "Bus size is not fixed '$ModuleName.$Wire->{ name }'" )
		#	if(
		#		( $Wire->{ attr } & ( $ATTR_WEAK_W | $ATTR_DC_WEAK_W | $ATTR_DEF )) == $ATTR_WEAK_W &&
		#		( $iModuleMode & $MODMODE_TEST ) == 0
		#	);
	}
	
	if( $Debug ){
		@WireListBuf = sort( @WireListBuf );
		
		printf( "Wire info : Unresolved:%3d / Added:%3d ( $ModuleName\@$DefFile )\n",
			$WireCntUnresolved, $WireCntAdded );
		
		if( !open( $fpList, ">> $ListFile" )){
			Error( "can't open file \"$ListFile\"" );
			return;
		}
		
		print( $fpList "*** $ModuleName wire list ***\n" );
		print( $fpList @WireListBuf );
		close( $fpList );
	}
}

### expand bus ###############################################################

sub ExpandBus{
	
	my(
		$Name,
		$Attr,
		$BitWidth,
		$Wire
	);
	
	foreach $Wire ( @WireList ){
		if( $Wire->{ name } =~ /\$n/ && $Wire->{ width } ne "" ){
			
			# Ÿ�����٤��Х�
			
			$Name		= $Wire->{ name };
			$Attr		= $Wire->{ attr };
			$BitWidth	= $Wire->{ width };
			
			# FR wire �ʤ� F �Ȥߤʤ�
			
			if(( $Attr & ( $ATTR_FIX | $ATTR_REF )) == ( $ATTR_FIX | $ATTR_REF )){
				$Attr &= ~$ATTR_REF
			}
			
			if( $Attr & ( $ATTR_REF | $ATTR_BYDIR )){
				ExpandBus2( $Name, $BitWidth, $Attr, 'ref' );
			}
			
			if( $Attr & ( $ATTR_FIX | $ATTR_BYDIR )){
				ExpandBus2( $Name, $BitWidth, $Attr, 'fix' );
			}
			
			# List ����ν���
			
			$Wire->{ attr } |= ( $ATTR_REF | $ATTR_FIX );
		}
		
		$Wire->{ name } =~ s/\$n//g;
	}
}

sub ExpandBus2{
	
	my( $Wire, $BitWidth, $Attr, $Dir ) = @_;
	my(
		$WireNum,
		$WireBus,
		$uMSB, $uLSB
	);
	
	# print( "ExBus2>>$Wire, $BitWidth, $Dir\n" );
	$WireBus =  $Wire;
	$WireBus =~ s/\$n//g;
	
	# $BitWidth ���� MSB, LSB ����Ф�
	if( $BitWidth =~ /(\d+):(\d+)/ ){
		$uMSB = $1;
		$uLSB = $2;
	}else{
		$uMSB = $BitWidth;
		$uLSB = 0;
	}
	
	# assign HOGE = {
	
	PrintRTL( "\tassign " );
	PrintRTL( "$WireBus = " ) if( $Dir eq 'ref' );
	PrintRTL( "{\n" );
	
	# bus �γ� bit �����
	
	for( $BitWidth = $uMSB; $BitWidth >= $uLSB; --$BitWidth ){
		$WireNum = $Wire;
		$WireNum =~ s/\$n/$BitWidth/g;
		
		PrintRTL( "\t\t$WireNum" );
		PrintRTL( ",\n" ) if( $BitWidth );
		
		# child wire ����Ͽ
		
		RegisterWire( $WireNum, "", $Attr, $ModuleName );
	}
	
	# } = hoge;
	
	PrintRTL( "\n\t}" );
	PrintRTL( " = $WireBus" ) if( $Dir eq 'fix' );
	PrintRTL( ";\n\n" );
}

### 10:2 ������ɽ���ΥХ����� get ���� #######################################

sub GetBusWidth {
	local( $_ ) = @_;
	
	if( $_ =~ /^(\d+):(\d+)$/ ){
		return( $1, $2 );
	}elsif( $_ eq '' ){
		return( 0, 0 );
	}
	
	Warning( "unknown bit width [$_]" );
	return( -3, -1 );
}

sub GetBusWidth2 {
	my( $MSB, $LSB ) = GetBusWidth( @_ );
	return( $MSB + 1 - $LSB );
}

### Format bus width #########################################################

sub FormatBusWidth {
	local( $_ ) = @_;
	
	if( /^\d+$/ ){
		die( "FormatBusWidth()\n" );
		return "[$_:0]";
	}else{
		return "[$_]";
	}
}

### repeat output ############################################################
# syntax:
#   $repeat( [ name: ] REPEAT_NUM ) or $repeat( [ name: ] start [, stop [, step ]] )
#      ....
#   $end
#	
#	%d �Ȥ� %{name}d �Ǥ�����ִ�

sub RepeatOutput{
	my( $BlockMode, $RepCntEd ) = @_;
	my( $RewindPtr ) = tell( $fpIn );
	my( $LineCnt ) = $.;
	my( $RepCnt );
	my( $VarName );
	
	my( $RepCntSt, $Step );
	
	if( $BlockNoOutput ){
		# ����ϥ֥�å���ϡ�repeat �ΰ�����̤����Υޥ���
		# �������Ƥ����ǽ��������Τǡ������������˽���
		ExpandRepeatOutput( $BLKMODE_REPEAT, 1 );
		return;
	}
	
	$RepCntEd = ExpandMacro( $RepCntEd, $EX_CPP | $EX_STR );
	
	# VarName ����
	if( $RepCntEd =~ /\s*\(\s*(\w+)\s*:/ ){
		$VarName = $1;
		$RepCntEd = "($'";
	}
	
	( $RepCntSt, $RepCntEd, $Step ) = Evaluate2( $RepCntEd );
	
	if( !defined( $RepCntEd )){
		if( $RepCntSt < 0 ){
			( $RepCntSt, $RepCntEd ) = ( -$RepCntSt - 1, -1 );
		}else{
			( $RepCntSt, $RepCntEd ) = ( 0, $RepCntSt );
		}
	}
	
	if( !defined( $Step )){
		$Step = $RepCntSt > $RepCntEd ? -1 : 1;
	}
	
	if( !IsNumber( $RepCntSt ) || !IsNumber( $RepCntEd ) || !IsNumber( $Step )){
		Error( "\$repeat() parameter isn't a number: ($RepCntSt,$RepCntEd,$Step)" );
		$RepCntEd = 0;
	}
	
	# ��ԡ��ȿ� <= 0 �����к�
	if( $RepCntSt == $RepCntEd ){
		ExpandRepeatOutput( $BLKMODE_REPEAT, 1 );
		return;
	}
	
	my $PrevRepCnt;
	$PrevRepCnt = $DefineTbl{ __REP_CNT__ }{ macro } if( defined( $DefineTbl{ __REP_CNT__ } ));
	
	for(
		$RepCnt = $RepCntSt;
		( $RepCntSt < $RepCntEd ) ? $RepCnt < $RepCntEd : $RepCnt > $RepCntEd;
		$RepCnt += $Step
	){
		AddCppMacro( '__REP_CNT__', $RepCnt, undef, 1 );
		AddCppMacro( $VarName, $RepCnt, undef, 1 ) if( defined( $VarName ));
		
		seek( $fpIn, $RewindPtr, $SEEK_SET );
		$. = $LineCnt;
		ExpandRepeatOutput( $BLKMODE_REPEAT );
	}
	
	if( defined( $PrevRepCnt )){
		AddCppMacro( '__REP_CNT__', $PrevRepCnt, undef, 1 );
	}else{
		delete( $DefineTbl{ __REP_CNT__ } );
	}
	delete( $DefineTbl{ $VarName } ) if( defined( $VarName ));
}

sub IsNumber {
	$_[ 0 ] != 0 || $_[ 0 ] =~ /^0/;
}

### Exec perl ################################################################
# syntax:
#   $perl EOF
#      ....
#   EOF

sub ExecPerl {
	local $_;
	
	# print buffer �ڤ��ؤ�
	my $PrevPrintBuf = $PrintBuf;
	$PrintBuf = \$PerlBuf;
	
	# perl code ����
	ExpandRepeatOutput( $BLKMODE_PERL );
	$PrintBuf = $PrevPrintBuf;
	
	$PerlBuf =~ s/^\s*#.*$//gm;
	$PerlBuf = ExpandMacro( $PerlBuf, $EX_INTFUNC | $EX_STR | $EX_COMMENT | $EX_NOREAD );
	
	if( $Debug ){
		print( "\n=========== perl code =============\n" );
		print( $PerlBuf );
		print( "\n===================================\n" );
	}
	$_ = ();
	$_ = eval( $PerlBuf );
	Error( $@ ) if( $@ ne '' );
	if( $Debug ){
		print( "\n=========== output code =============\n" );
		print( $_ );
		print( "\n===================================\n" );
	}
	
	$_ .= "\n" if( $_ ne '' && !/\n$/ );
	PrintRTL( $_ );
	$ResetLinePos = $.;
}

### enum state ###############################################################
# syntax:
#	enum|enum_p [<type name>] { <n0> [, <n1> ...] } [<reg name> ];
#   enum �� define ����ѡ�enum_p �� parameter �����
# module ��ʤ� parameter��module ���ʤ� define

sub Enumerate{
	
	my( $Line, $bParam ) = @_;
	local( $_ )  = $Line;
	my(
		$TypeName,
		@EnumList,
		$BitWidth,
		$i
	);
	
	# ; �ޤ� Buf ��ί�����
	
	if( $Line !~ /;/ ){
		while( $Line = ReadLine( $fpIn )){
			$_ .= $Line;
			last if( $Line =~ /;/ );
		}
	}
	
	# delete comment
	s/<__COMMENT_\d+__>//g;
	
	# delete \n
	
	s/\n+/ /g;
	s/\x0D//g;
	
	# compress blank
	
	s/,/ /g;
	s/;/ /g;
	s/\s+/ /g;
	s/ *(\W) */$1/g;
	s/^ //g;
	s/ $//g;
	
	#print( "enum>>$_\n" );
	
	# get typedef name
	
	if( /(.+)({.*)/ ){
		$TypeName	= $1;
		$_		= $2;
	}
	
	# make enum list
	
	$_  =~ s/{(.*?)}(.*)/$2/g;
	$Line = $1;
	
	@EnumList = split( / /, $1 );
	$BitWidth = int( log( $#EnumList + 1 ) / log( 2 ));
	++$BitWidth if( log( $#EnumList + 1 ) / log( 2 ) > $BitWidth );
	
	#print( "enum>>$BitWidth, @EnumList\n" );
	
	$i = $BitWidth - 1;
	if( $TypeName ne "" ){
		AddCppMacro( $TypeName, "[$i:0]" );
		AddCppMacro( "${TypeName}_w", $BitWidth );
	}
	
	# enum list �� define ����
	for( $i = 0; $i <= $#EnumList; ++$i ){
		if( $bParam ){
			PrintRTL( "\tparameter\t$EnumList[ $i ]\t= $BitWidth\'d$i;\n" );
		}else{
			AddCppMacro( $EnumList[ $i ], "$BitWidth\'d$i" );
		}
	}
}

### print all inputs #########################################################

sub PrintAllInputs {
	my( $Param, $Tab ) = @_;
	my( $Wire );
	
	$Param	=~ s/^\s*(\S+).*/$1/;
	$Tab	=~ /^(\s*)/; $Tab = $1;
	$_		= ();
	
	foreach $Wire ( @WireList ){
		if( $Wire->{ name } =~ /^$Param$/ && QueryWireType( $Wire, '' ) eq 'input' ){
			$_ .= $Tab . $Wire->{ name } . ",\n";
		}
	}
	
	s/,([^,]*)$/$1/;
	PrintRTL( $_ );
}

### AutoFix Hi-Z signals #####################################################
# syntax:
#   $AutoFix <no/off>
#
# ��������:
#  [3:2] �� LSB �� 0 �Ǥʤ���Τˤ�Ŭ���Բ�
#  wire ��� instance �Υݡ��������礭���ȡ�

### requre ###################################################################

sub Require {
	if( $_[0] =~ /"(.*)"/ ){
		require $1;
	}else{
		Error( "Illegal requre file name" )
	}
}

### Tab �ǻ������Υ��ڡ���������� ###########################################

sub TabSpace {
	local $_;
	my( $Width, $TabWidth ) = @_;
	( $_, $Width, $TabWidth ) = @_;
	$_ . "\t" x int(( $Width - length( $_ ) + $TabWidth - 1 ) / $TabWidth );
}

### CPP directive ���� #######################################################

sub AddCppMacro {
	my( $Name, $Macro, $Args, $bNoCheck ) = @_;
	
	$Macro	= '1' if( !defined( $Macro ));
	$Args	= 's' if( !defined( $Args ));
	
	if(
		( !defined( $bNoCheck ) || !$bNoCheck ) &&
		defined( $DefineTbl{ $Name } ) &&
		( $DefineTbl{ $Name }{ args } ne $Args || $DefineTbl{ $Name }{ macro } != $Macro )
	){
		Warning( "redefined macro '$Name'" );
	}
	
	$DefineTbl{ $Name } = { 'args' => $Args, 'macro' => $Macro };
}

### if �֥�å��� eval #######################################################

sub IfBlockEval {
	local( $_ ) = @_;
	
	# defined �ִ�
	s/\bdefined\s+($CSymbol)/defined( $DefineTbl{ $1 } ) ? 1 : 0/ge;
	return Evaluate( ExpandMacro( $_, $EX_CPP | $EX_STR | $EX_NOREAD ));
}

### CPP �ޥ���Ÿ�� ###########################################################

sub ExpandMacro {
	local $_;
	my $Mode;
	
	( $_, $Mode ) = @_;
	
	my $Line;
	my $Line2;
	my $Name;
	my( $ArgList, @ArgList );
	my $ArgNum;
	my $i;
	
	$Mode = $EX_CPP | $EX_REP if( !defined( $Mode ));
	
	if( $BlockRepeat && $Mode & $EX_REP ){
		s/%(?:\{(.+?)\})?([+\-\d\.#]*[%cCdiouxXeEfgGnpsS])/ExpandPrintfFmtSub( $2, $1 )/ge;
	}
	
	my $bReplaced = 1;
	if( $Mode & $EX_CPP ){
		while( $bReplaced ){
			$bReplaced = 0;
			$Line = '';
			
			while( /\b($CSymbol)\b(.*)/s ){
				$Line .= $`;
				( $Name, $_ ) = ( $1, $2 );
				
				if( $Name eq '__FILE__' ){		$Line .= $DefFile;
				}elsif( $Name eq '__LINE__' ){	$Line .= $.;
				}elsif( !defined( $DefineTbl{ $Name } )){
					# �ޥ���ǤϤʤ�
					$Line .= $Name;
				}elsif( $DefineTbl{ $Name }{ args } eq 's' ){
					# ñ��ޥ���
					$Line .= $DefineTbl{ $Name }{ macro };
					$bReplaced = 1;
				}else{
					# �ؿ��ޥ���
					s/^\s+//;
					
					if( !/^\(/ ){
						# hoge( �ˤʤäƤʤ�
						Error( "invalid number of macro arg: $Name" );
						$Line .= $Name;
					}else{
						# �ޥ����������
						$_ = GetFuncArg( $fpIn, $_ );
						
						# �ޥ����������
						if( /^($OpenClose)(.*)/s ){
							( $ArgList, $_ ) = ( $1, $2 );
							$ArgList =~ s/<__COMMENT_\d+__>//g;
							$ArgList =~ s/[\t ]*[\x0D\x0A]+[\t ]*/ /g;
							$ArgList =~ s/^\(\s*//;
							$ArgList =~ s/\s*\)$//;
							
							undef( @ArgList );
							
							while( $ArgList ne '' ){
								last if( $ArgList !~ /^\s*($OpenCloseArg)\s*(,?)\s*(.*)/ );
								push( @ArgList, $1 );
								$ArgList = $3;
								
								if( $2 ne '' && $ArgList eq '' ){
									push( @ArgList, '' );
								}
							}
							
							if( $ArgList eq '' ){
								# ���������å�
								$ArgNum = $DefineTbl{ $Name }{ args };
								$ArgNum = -$ArgNum - 1 if( $ArgNum < 0 );
								
								if( !(
									$DefineTbl{ $Name }{ args } >= 0 ?
										( $ArgNum == $#ArgList + 1 ) : ( $ArgNum <= $#ArgList + 1 )
								)){
									Error( "invalid number of macro arg: $Name" );
									$Line .= $Name . '()';
								}else{
									# ��������°������ִ�
									$Line2 = $DefineTbl{ $Name }{ macro };
									$Line2 =~ s/<__ARG_(\d+)__>/$ArgList[ $1 ]/g;
									
									# ���Ѱ������ִ�
									if( $DefineTbl{ $Name }{ args } < 0 ){
										if( $#ArgList + 1 <= $ArgNum ){
											# ���� 0 �Ĥλ��ϡ�����ޤ��Ȥ�ä�
											$Line2 =~ s/,?\s*(?:##)*\s*__VA_ARGS__\s*/ /g;
										}else{
											$Line2 =~ s/(?:##\s*)?__VA_ARGS__/join( ', ', @ArgList[ $ArgNum .. $#ArgList ] )/ge;
										}
									}
									$Line .= $Line2;
									$bReplaced = 1;
								}
							}else{
								# $ArgList ���������񤷤���ʤ��ä��饨�顼
								Error( "invalid macro arg: $Name" );
								$Line .= $Name . '()';
							}
						}
					}
				}
			}
			$_ = $Line . $_;
		}
		
		# �ȡ�����Ϣ��黻�� ##
		$bReplaced |= s/\s*##\s*//g;
	}
	
	if( $Mode & $EX_INTFUNC ){
		s/\bsizeof($OpenClose)/SizeOf( $1, $Mode )/ge;
		s/\btypeof($OpenClose)/TypeOf( $1, $Mode )/ge;
		s/\$Eval($OpenClose)/Evaluate( ExpandMacro( $1 , $EX_STR | $EX_NOREAD ))/ge;
	}
	
	if( $Mode & $EX_RMSTR ){
		s/<__STRING_\d+__>/ /g;
	}elsif( $Mode & $EX_STR ){
		# ʸ����
		s/\$String($OpenClose)/Stringlize( $1 )/ge;
		
		# ʸ�����������
		s/<__STRING_(\d+)__>/$CommentPool[ $1 ]/g;
		
		# ʸ�����ƥ��Ϣ��
		1 while( s/((?<!\\)".*?)(?<!\\)"\s*"(.*?(?<!\\)")/$1$2/g );
	}
	
	# ������
	if( $Mode & $EX_RMCOMMENT ){
		s/<__COMMENT_\d+__>/ /g;
	}elsif( $Mode & $EX_COMMENT ){
		s/<__COMMENT_(\d+)__>/$CommentPool[ $1 ]/g;
	}
	
	$_;
}

sub ExpandPrintfFmtSub {
	my( $Fmt, $Name ) = @_;
	my $Num;
	
	if( !defined( $Name )){
		$Name = '__REP_CNT__';
	}
	if( !defined( $DefineTbl{ $Name } )){
		Error( "repeat var not defined '$Name'" );
		return( 'undef' );
	}
	return( sprintf( "%$Fmt", $DefineTbl{ $Name }{ macro } ));
}

### sizeof / typeof ##########################################################

sub SizeOf {
	local( $_ );
	my( $Flag );
	( $_, $Flag ) = @_;
	
	my $Wire = 0;
	my $Bits = 0;
	
	return 'x' if( $Flag & $EX_NOSIGINFO );
	
	while( s/($CSymbol)// ){
		if( !defined( $Wire = $WireList{ $1 } )){
			Error( "undefined wire '$1'" );
		}elsif( $Wire->{ width } =~ /(\d+):(\d+)/ ){
			$Bits += ( $1 - $2 + 1 );
		}else{
			++$Bits;
		}
	}
	$Bits;
}

sub TypeOf {
	local( $_ );
	my( $Flag );
	( $_, $Flag ) = @_;
	
	return '[?]' if( $Flag & $EX_NOSIGINFO );
	
	if( !/($CSymbol)/ ){
		Error( "syntax error (typeof)" );
		$_ = '';
	}elsif( !defined( $_ = $WireList{ $1 } )){
		Error( "undefined wire '$1'" );
		$_ = '';
	}else{
		$_ = $_->{ width } eq '' ? '' : "[$_->{ width }]";
	}
	$_;
}

sub Stringlize {
	local( $_ ) = @_;
	
	s/^\(\s*//;
	s/\s*\)$//;
	
	return "\"$_\"";
}

### �ե����� include #########################################################

sub Include {
	local( $_ ) = @_;
	
	$_ = ExpandMacro( $_, $EX_CPP | $EX_STR | $EX_NOREAD );
	$_ = $1 if( /"(.*?)"/ );
	
	my $RewindPtr	= tell( $fpIn );
	my $LineCnt		= $.;
	my $PrevDefFile	= $DefFile;
	
	close( $fpIn );
	
	if( !open( $fpIn, "< $_" )){
		Error( "can't open include file '$_'" );
	}else{
		$DefFile = $_;
		PrintRTL( "# 1 \"$_\"\n" );
		print( "including file '$_'...\n" ) if( $Debug );
		ExpandRepeatOutput();
		print( "back to file '$PrevDefFile'...\n" ) if( $Debug );
	}
	$DefFile = $PrevDefFile;
	open( $fpIn, "< $DefFile" );
	
	seek( $fpIn, $RewindPtr, $SEEK_SET );
	$. = $LineCnt;
	$ResetLinePos = $.;
}

##############################################################################

__DATA__
#define BUSTYPE( w )	[$Eval( w - 1 ):0]
#define WIDTH( w )		$Eval(( w ) >= 2 ? int( log(( w ) * 2 - 1 ) / log( 2 )) : 1 )
#define X( w )			{ w { 1'bx }}
#define H( w )			{ w { 1'b1 }}
#define HEX_V( w, v )	$Eval( sprintf(( w ) . "'h%0" . int((( w ) + 3 ) / 4 ) . "x", v ))
#define BIN_V( w, v )	$Eval( sprintf(( w ) . "'b%0" . ( w ) . "b", v ))
#define NULL			$Eval( '' )
