#!/usr/bin/perl

##############################################################################
#
#		vpp -- verilog preprocessor		Ver.2.00
#		Copyright(C) by DDS
#
##############################################################################
#
#	2013.01.16	2��������θ��� [...] ��ȿ�����Ƥ��������ʤäƤ��Τ���
#	2013.01.17	$repeat �Υͥ��Ȥ��б�
#	2013.01.18	GetModuleIO() �� parameter �� wire �����ˤ���
#	2013.12.12	perlpp ��¢
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
my $ATTR_NC			= 0xFFFFFFFF;

$enum = 0;
my $BLKMODE_NORMAL	= $enum++;	# �֥�å���
my $BLKMODE_REPEAT	= $enum++;	# repeat �֥�å�
my $BLKMODE_PERL	= $enum++;	# perl �֥�å�
my $BLKMODE_IF		= $enum++;	# if �֥�å�
my $BLKMODE_ELSE	= $enum++;	# else �֥�å�

$enum = 1;
my $EXPAND_CPP		= $enum;		# CPP �ޥ���Ÿ��
my $EXPAND_REP		= $enum <<= 1;	# repeat �ޥ���Ÿ��
my $EXPAND_EVAL		= $enum <<= 1;	# $Eval Ÿ��

my $MODMODE_NORMAL	= 0;
my $MODMODE_TEST	= 1 << 0;
my $MODMODE_INC		= 1 << 1;
my $MODMODE_TESTINC	= $MODMODE_TEST | $MODMODE_INC;

my $CSymbol			= '\b[_a-zA-Z]\w*\b';
my $DefSkelPort		= "(.*)";
my $DefSkelWire		= "\$1";

my $tab0 = 4 * 2;
my $tab1 = 4 * 7;
my $tab2 = 4 * 13;

my $ErrorCnt = 0;
my $TabWidth = 4;	# ������

my $TabWidthType	= 8;	# input / output ��
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
my $BlockNoOutput = 0;
my $BlockRepeat = 0;

# ����ơ��֥�ط�
my @WireList;
my %WireList;
my @SkelList;
my $iModuleMode;
my $PortList;
my $PortDef;
my %DefineTbl;
my %EnumListWidth;

main();
exit( $ErrorCnt != 0 );

### main procedure ###########################################################

sub main{
	local( $_ );
	
	if( $#ARGV < 0 ){
		print( "usage: vpp.pl <Def file>\n" );
		return;
	}
	
	# -DMACRO setup
	
	while( 1 ){
		$_ = $ARGV[ 0 ];
		
		if    ( /^-v/		){ $Debug = 1;
		}elsif( /^-I(.*)/	){ push( @INC, $1 );
		}elsif( /^-D(.+?)=(.+)/ ){
			AddCppMacro( $1, $2 );
		}elsif( /^-D(.+)/ ){
			AddCppMacro( $1 );
		}elsif( /^-tab(.*)/	){
			$ExpandTab = 1;
			$TabWidth = eval( $1 );
		}else{
			last;
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
	
	unlink( $ListFile );
	
	# expand $repeat
	if( !open( fpDef, "< $DefFile" )){
		Error( "can't open file \"$DefFile\"" );
		return;
	}
	
	open( fpRTL, "> $CppFile" );
	
	ExpandRepeatOutput();
	
	if( $Debug ){
		print( "=== macro ===\n" );
		foreach $_ ( sort keys %DefineTbl ){
			printf( "$_%s\t$DefineTbl{ $_ }{ 'macro' }\n", $DefineTbl{ $_ }{ 'args' } eq 's' ? '' : '()' );
		}
		print( "=============\n" );
	}
	undef( %DefineTbl );
	
	close( fpRTL );
	close( fpDef );
	
	system( "cp $CppFile stage1" ) if( $Debug );
	
	# vpp
	if( !open( fpDef, "< $CppFile" )){
		Error( "can't open file \"$CppFile\"" );
		return;
	}
	
	$ExpandTab ?
		open( fpRTL, "| expand -$TabWidth > $RTLFile" ) :
		open( fpRTL, "> $RTLFile" );
	
	MultiLineParser();
	
	close( fpRTL );
	close( fpDef );
	
	unlink( $CppFile );
	
	#unlink( $RTLFile ) if( $ErrorCnt );
}

### �ޥ���饤��ѡ��� #######################################################

sub MultiLineParser {
	local( $_ );
	my( $Line, $Word );
	
	while( <fpDef> ){
		$_ = ExpandMacro( $_, $EXPAND_CPP | $EXPAND_EVAL );
		( $Word, $Line ) = GetWord( $_ );
		
		if    ( /^#/					){ CppDirectiveLine( $_ );
		}elsif( $Word eq 'module'		){ StartModule( $Line );
		}elsif( $Word eq 'module_inc'	){ StartModule( $Line ); $iModuleMode = $MODMODE_INC;
		}elsif( $Word eq 'endmodule'	){ EndModule( $_ );
		}elsif( $Word eq 'instance'		){ DefineInst( $Line );
		}elsif( $Word eq 'enum'			){ Enumerate( $Line );
		}elsif( $Word eq '$wire'		){ DefineDefWireSkel( $Line );
		}elsif( $Word eq '$header'		){ OutputHeader();
		}elsif( $Word eq 'testmodule'	){ StartModule( $Line ); $iModuleMode = $MODMODE_TEST;
		}elsif( $Word eq 'testmodule_inc'){StartModule( $Line ); $iModuleMode = $MODMODE_TESTINC;
		}elsif( $Word eq '$AllInputs'	){ PrintAllInputs( $Line, $_ );
		}elsif(
			$Word eq '_module' ||
			$Word eq '_endmodule'
		){
			$_ =~ s/\b_((?:end)?module)\b/$1/;
			PrintRTL( $_ );
		}else{
			PrintRTL( $_ );
		}
	}
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
	
	while( <fpDef> ){
		# ���ɽ���θߴ���
		s/\$(repeat|perl)/#$1/g;
		s/\$end\b/#endrep/g;
		s/\bEOF\b/#endperl/g;
		
		if( /^\s*#\s*(?:if|ifdef|ifndef|elif|else|endif|define|undef|include|require|repeat|endrep|perl|endperl)\b/	){
			
			# \ �ǽ���äƤ���Ԥ�Ϣ��
			while( /\\$/ ){
				if( !( $Line = <fpDef> )){
					last;
				}
				$_ .= $Line;
			}
			
			PrintRTL( sprintf( "# %d \"$DefFile\"\n", $. + 1 ));
			
			# ����������
			s#[\t ]*/\*.*?\*/[\t ]*# #gs;
			s#[\t ]*//.*$##gm;
			
			# \ ���
			s/[\t ]*\\[\x0D\x0A]+[\t ]*/ /g;
			s/\s+$//g;
			s/^\s*#\s*//;
			
			$_ = ExpandMacro( $_, $EXPAND_REP );
			
			# $DefineTbl{ $1 }{ 'args' }:  >=0: ����  <0: ���Ѱ���  's': ñ��ޥ���
			# $DefineTbl{ $1 }{ 'macro' }:  �ޥ����������
			
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
				RepeatOutput( $BlockMode, ExpandMacro( $1 ));
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
			}elsif( !$BlockNoOutput ){
				if( /^define\s+($CSymbol)$/ ){
					# ̾���������
					AddCppMacro( $1 );
				}elsif( /^define\s+($CSymbol)\s+(.+)/ ){
					# ̾���������
					AddCppMacro( $1, $2 );
				}elsif( /^define\s+($CSymbol)($OpenClose)\s+(.+)/ ){
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
						$Macro =~ s/\b$ArgList[ $i ]\b/__\$ARG_${i}\$__/g;
					}
					
					AddCppMacro( $Name, $Macro, $ArgNum );
				}elsif( /^undef\s+($CSymbol)$/ ){
					# undef
					delete( $DefineTbl{ $1 } );
				}elsif( /^include\s*"(.*?)"/ ){
					Include( $1 );
				}elsif( /^require\s+(.*)/ ){
					Require( $1 );
				}
			}
		}elsif( !$BlockNoOutput ){
			PrintRTL( ExpandMacro( $_ ));
		}
	}
	
	$BlockNoOutput	>>= 1;
	$BlockRepeat	>>= 1;
}

### Start of the module #####################################################

sub StartModule{
	my( $Line ) = @_;
	my(
		@ModuleIO,
		@IOList,
		$InOut,
		$BitWidth,
		$Attr,
		$Port
	);
	
	# wire list �����
	
	@WireList	= ();
	%WireList	= ();
	$iModuleMode	= $MODMODE_NORMAL;
	$PortList		= '';
	$PortDef		= '';
	
	$PrintBuf	= \$RTLBuf;
	$RTLBuf		= "";
	
	( $ModuleName, $Line ) = GetWord( $Line );
	$RTLFile = $1 if( $Line =~ /^\s*([^;\(\s]+)/ );
	
	#PrintRTL( SkipToSemiColon( $Line ));
	#SkipToSemiColon( $Line );
	
	# ); �ޤ��ɤ� �����ɤ᤿�餽���ݡ��ȥꥹ�ȤȤߤʤ�
	
	if( $Line !~ /^\s*;/ ){
		
		my( $CLikePortDef ) = 0;
		
		while( <fpDef> ){
			last if( /\s*\);/ );
			next if( /^\s*\(\s*$/ || /^#/ );
			
			$CLikePortDef |= /^\s*(?:wire|reg|input|output|outreg|inout|ioreg)\b/;
			
			/^\s*(wire|reg\t?|input|output|outreg|inout|ioreg)\s*(\[[^\]]+\])?\s*(.*)/;
			if( $1 ){
				#if( $2 eq '' ){
				if( !defined( $2 )){
					$_ =	TabSpace( $1, $TabWidthType, $TabWidth ) .
							TabSpace( '', $TabWidthBit,  $TabWidth ) .
							$3 . "\n";
				}else{
					$_ =	TabSpace( $1, $TabWidthType, $TabWidth ) .
							TabSpace( $2, $TabWidthBit,  $TabWidth ) .
							$3 . "\n";
				}
			}else{
				s|^[ \t]+||;
			}
			$PortDef .= $_;
			
			next if( /^\s*(?:reg|wire|parameter)\b/ );
			
			s/^(?:input|output|outreg|inout|ioreg)\s+(?:\[[^\]]+\])?\s*//g;
			s/^/\t/;
			s/;/,/;
			$PortList .= $_;
		}
		
		$PortDef	= '' if( !$CLikePortDef );
		$PortList	= '' if( !$CLikePortDef );
	}
	
	# �� module �� wire / port �ꥹ�Ȥ�get
	
	@ModuleIO = GetModuleIO( $ModuleName, $CppFile );
	
	# input/output ʸ 1 �Ԥ��Ȥν���
	
	while( $Line = shift( @ModuleIO )){
		
		( $InOut, $BitWidth, @IOList )	= split( /\t/, $Line );
		
		while( $Port = shift( @IOList )){
			
			$Attr = ( $InOut eq "input" )	? ( $ATTR_DEF | $ATTR_IN )	:
					( $InOut eq "output" )	? ( $ATTR_DEF | $ATTR_OUT )	:
					( $InOut eq "inout" )	? ( $ATTR_DEF | $ATTR_INOUT ):
					( $InOut eq "wire" )	? ( $ATTR_DEF | $ATTR_WIRE )	:
					( $InOut eq "reg" )		? ( $ATTR_DEF | $ATTR_WIRE | $ATTR_REF )	:
					( $InOut eq "assign" )	? ( $ATTR_FIX | $ATTR_WEAK_W ):
											  0;
			
			if( $BitWidth eq '?' ){
				$Attr |= $ATTR_WEAK_W;
				#$BitWidth = "X";
			}
			
			$BitWidth = "X" if( $InOut eq "assign" );
			RegisterWire( $Port, $BitWidth, $Attr, $ModuleName );
		}
	}
}

### End of the module ########################################################

sub EndModule{
	my( $Line ) = @_;
	my(
		$Type,
		$bFirst,
		$Wire
	);
	
	my( $MSB, $LSB, $MSB_Drv, $LSB_Drv );
	
	# expand bus
	
	ExpandBus();
	
	PrintRTL( '//' ) if( $iModuleMode & $MODMODE_INC );
	PrintRTL( $Line );
	undef( $PrintBuf );
	
	# module port �ꥹ�Ȥ����
	
	$bFirst = 1;
	PrintRTL( '//' ) if( $iModuleMode & $MODMODE_INC );
	PrintRTL( "module $ModuleName" );
	
	if( $iModuleMode == $MODMODE_NORMAL ){
		
		my $bCLikePortDef = $PortList ne "";
		
		foreach $Wire ( @WireList ){
			$Type = QueryWireType( $Wire, $bCLikePortDef ? 'd' : '' );
			
			if( $Type eq "input" || $Type eq "output" || $Type eq "inout" ){
				$PortList .= "\t$Wire->{ 'name' },\n";
			}
		}
		
		if( $PortList ){
			$PortList =~ s/,([^,]*)$/$1/;
			PrintRTL( "(\n$PortList)" );
		}
		
	}
	
	PrintRTL( ";\n$PortDef" );
	
	# in/out/reg/wire �������
	
	foreach $Wire ( @WireList ){
		if(( $Type = QueryWireType( $Wire, "d" )) ne "" ){
			
			if( $iModuleMode & $MODMODE_TEST ){
				$Type = "reg"  if( $Type eq "input" );
				$Type = "wire" if( $Type eq "output" || $Type eq "inout" );
			}elsif( $iModuleMode & $MODMODE_INC ){
				# ��ƥ��ȥ⥸�塼��� include �⡼�ɤǤϡ��Ȥꤢ�������� wire �ˤ���
				$Type = 'wire';
			}
			
			PrintRTL( TabSpace( $Type, $TabWidthType, $TabWidth ));
			
			if( $Wire->{ 'width' } eq "" ){
				# bit ����ʤ�
				PrintRTL( TabSpace( '', $TabWidthBit, $TabWidth ));
			}else{
				# 10:2 �Ȥ�
				PrintRTL( TabSpace( FormatBusWidth( $Wire->{ 'width' } ), $TabWidthBit, $TabWidth ));
			}
			
			PrintRTL( "$Wire->{ 'name' };\n" );
		}
	}
	
	# buf �ˤ���Ƥ������Ҥ�ե�å���
	
	print( fpRTL $RTLBuf );
	$RTLBuf = "";
	
	# wire �ꥹ�Ȥ���� for debug
	OutputWireList();
}

### Evaluate #################################################################

sub EvaluateLine {
	local( $_ ) = @_;
	s/\$Eval($OpenClose)/Evaluate($1)/ge;
	$_;
}

sub Evaluate {
	local( $_ ) = @_;
	
	s/\$Eval//g;
	$_ = eval( $_ );
	Error( $@ ) if( $@ ne '' );
	return( $_ );
}

sub Evaluate2 {
	local( $_ ) = @_;
	local( @_ );
	
	s/\$Eval//g;
	@_ = eval( $_ );
	Error( $@ ) if( $@ ne '' );
	return( @_ );
}

### output normal line #######################################################

sub PrintRTL{
	local( $_ ) = @_;
	my( $tmp );
	
	# outreg / ioreg ����
	
	if( /\b(out|io)reg\b/ ){
		$tmp = $_;
		
		s/\boutreg\b/output/g || s/\bioreg\b/inout/g;
		$tmp =~ s/\b(out|io)reg\b/reg\t/g;
		
		$_ .= $tmp . sprintf( "# %d \"$DefFile\"\n", $. + 1 );
	}
	
	# Case / FullCase ����
	
	s|\bC(asex?\s*\(.*\))|c$1 /* synopsys parallel_case */|g;
	s|\bFullC(asex?\s*\(.*\))|c$1 /* synopsys parallel_case full_case */|g;
	
	if( defined( $PrintBuf )){
		$$PrintBuf .= $_;
	}else{
		print( fpRTL $_ );
	}
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
	my( $Line ) = @_;
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
	
	if( $Line !~ /\s+([\w\d]+)(\s+#\([^\)]+\))?\s+(\S+)\s+"?(\S+)"?\s*([\(;])/ ){
#	if( $Line !~ /\s*,?\s*([\w\d]+)(\s+#\([^\)]+\))?\s*,?\s*(\S+)\s*,?\s*"?(\S+)"?\s*,?\s*([\(;])/ ){
		Error( "syntax error (instance)" );
		return;
	}
	
	# get module name, module inst name, module file
	
	my( $ModuleName, $ModuleParam, $ModuleInst, $ModuleFile ) = ( $1, $2, $3, $4 );
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
	
	while( $Line = shift( @ModuleIO )){
		
		( $InOut, $BitWidth, @IOList )	= split( /\t/, $Line );
		
		$InOut = "output" if( $InOut eq "outreg" );
		$InOut = "inout"  if( $InOut eq "ioreg" );
		
		next if( $InOut !~ /^(?:input|output|inout)$/ );
		
		while( $Port = shift( @IOList )){
			
			( $Wire, $Attr ) = ConvPort2Wire( $Port, $BitWidth );
			
			if( $Attr != $ATTR_NC ){
				
				# hoge(\d) --> hoge[$1] �к�
				
				$WireBus = $Wire;
				if( $WireBus  =~ /(.*)\[(\d+:?\d*)\]$/ ){
					
					$WireBus		= $1;
					$BitWidthWire	= $2;
					$BitWidthWire	= $BitWidthWire =~ /^\d+$/ ? "$BitWidthWire:$BitWidthWire" : $BitWidthWire;
					
					# instance �� tmpl �����
					#  hoge  hoge[1] �ʤɤΤ褦�� wire ¦�� bit ���꤬
					# �Ĥ����Ȥ� wire �μºݤΥ��������狼��ʤ�����
					# ATTR_WEAK_W °����Ĥ���
					$Attr |= $ATTR_WEAK_W;
				}else{
					
					# BusSize �� [BIT_DMEMADR-1:0] �ʤɤΤ褦�������ξ�硤? ���Ѵ�����롥
					# ���ΤȤ��� $ATTR_WEAK_W °����Ĥ���
					# ���ޤ� ? ���դ��Τ� typeof() �Τ�
					
					if( $BitWidth eq '?' ){
						$Attr |= $ATTR_WEAK_W;
						$BitWidthWire	= $BitWidth;
					}else{
						$BitWidthWire	= $BitWidth;
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
	
	my( $ModuleName, $ModuleFile ) = @_;
	my(
		$Line,
		$_,
		$bFound
	);
	
	$bFound = 0;
	
	if( !open( fpGetModuleIO, "< $ModuleFile" )){
		Error( "can't open file \"$ModuleFile\"" );
		return( "" );
	}
	
	# module ����Ƭ��õ��
	
	while( $Line = <fpGetModuleIO> ){
		
		if( $bFound ){
			# module ������
			
			last if( $Line =~ /\bendmodule\b/ );
			$_ .= $Line;
			
		}else{
			# module ��ޤ����Ĥ��Ƥ��ʤ�
			
			$bFound = 1 if( $Line =~ /\b(?:test)?module(?:_inc)?\s+$ModuleName\b/ );
		}
	}
	
	close( fpGetModuleIO );
	
	if( !$bFound ){
		Error( "can't find module \"$ModuleName\@$ModuleFile\"" );
		return( "" );
	}
	
	# delete comment
	
	s|//\*|// \*|g;
	s|/\*.*?\*/||gs;
	s/#.*//g;
	s|//.*||g;
	s/\btask\b.*?\bendtask\b//gs;
	s/\bfunction\b.*?\bendfunction\b//gs;
	s/^\s*`.*//g;
	
	# delete \n
	
	s/\n+/ /g;
	s/\x0D//g;
	
	# split
	
	#print if( $Debug );
	
	s/\b(end|endattribute|endcase|endfunction|endmodule|endprimitive|endspecify|endtable|endtask)\b/\n$1\n/g;
	s/;/;\n/g;
	s/[\t ]+/ /g;
	s/ *\n */\n/g;
	s/^ +//g;
	
	# port �ʳ�����
	
	s/(.*)/DeleteExceptPort($1)/ge;
	s/\s*\n+/\n/g;
	s/^\n//g;
	s/\n$//g;
	
	#print( "$ModuleName--------\n$_\n" );
	return( split( /\n/, $_ ));
}

sub DeleteExceptPort{
	local( $_ ) = @_;
	
	if( /^(input|output|inout|wire|reg|outreg|ioreg|parameter)\b/ ){
		
		my( $Type ) = $1 eq 'parameter' ? 'wire' : $1;
		my( $Width ) = '';
		
		$_ = $';
		
		#s/\[0:0\]/ /g;
		#s/\[(\d+):0\]/ $1 /g;
		
		# [10:2] �Ȥ����к������� MSB:LSB ���֤�
		if( /^\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]/ ){
			$Width = "$1:$2";
			$_ = $';
		}
		
		# ���ʳ��ΥХ�ɽ���ΤȤ��ϡ�[...] �򤽤Τޤ��֤�
		elsif( /^\s*(\[[^\]]+\])/ ){
			$Width = "$1";
			$_ = $';
		}
		
		# typeof()�ϡ������Х����ˤ��� (^^;
		elsif( /typeof\s*\([^\)]+\)/ ){
			$Width = '?';
			$_ = $';
		}
		
		# enum ���줿��Τ�?
		elsif( /^\s*($CSymbol)/ && defined( $EnumListWidth{ $1 } )){
			$Width = $EnumListWidth{ $1 };
			$_ = $';
		}
		
		s/\[.*?\]//g;	# 2��������θ������� [...] ����
		s/\s*=.*//g;	# wire hoge = hoge �� = �ʹߤ���
		
		s/^[\s:,]+//;
		s/[\s:,]+$//;
		s/[ ;,]+/\t/g;
		
		$_ = "$Type\t$Width\t$_";
		
	}elsif( /^assign\b/ ){
		# assign �Υ磻�䡼�ϡ�= ľ���μ��̻Ҥ����
		s/\s*=.*//g;
		/\s($CSymbol)$/;
		$_ = "assign\t$1";
	}else{
		$_ = '';
	}
	
	return( $_ );
}

### optimize line ( remove blank, etc... ) ###################################

sub OptimizeLine{
	local( $_ ) = @_;
	
	s/[\t ]+/ /g;
	s/\/\/.*//g;
	s/^ +//g;
	s/ +$//g;
	
	/^([\w\d\$]+)/;
	return( $_, $1 );
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
	
	print( fpRTL <<EOF );
/*****************************************************************************

	$RTLFile -- \$BaseName module	generated by vpp.pl
	
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
	}while( <fpDef> );
	
  ExitLoop:
	return( $_ );
}

### read port/wire tmpl list #################################################

sub ReadSkelList{
	
	my(
		$Line,
		$Port,
		$Wire,
		$AttrLetter
	);
	
	my $Attr = 0;
	my $Used = 0;
	
	while( $Line = <fpDef> ){
		$Line =~ s/\/\/.*//g;
		next if( $Line =~ /^\s*$/ );
		last if( $Line =~ /^\s*\);/ );
		
		$Line =~ /^\s*(\S+)\s*(\S*)\s*(\S*)/;
		
		( $Port, $Wire, $AttrLetter ) = ( $1, $2, $3 );
		
		if( $Wire =~ /^[MBU]?(?:NP|NC|W|I|O|IO|U)$/ ){
			$AttrLetter = $Wire;
			$Wire = "";
		}
		
		# attr
		
		$Attr = $ATTR_MD		if( $AttrLetter =~ /M/ );
		$Attr = $ATTR_DC_WEAK_W	if( $AttrLetter =~ /B/ );
		$Used = 1				if( $AttrLetter =~ /U/ );
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
			'used'	=> $Used
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
		if( !$Skel->{ 'used' } ){
			Warning( "unused template ( $Skel->{ 'port' } --> $Skel->{ 'wire' } \@ $_ )", $LineNo );
		}
	}
}

### convert port name to wire name ###########################################

sub ConvPort2Wire{
	
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
		next if( $BitWidth == 0 && $Skel->{ 'wire' } =~ /\$n/ );
		
		# Hit ����
		if( $Port =~ /^$Skel->{ 'port' }$/ ){
			# port tmpl ���Ѥ��줿
			$Skel->{ 'used' } = 1;
			
			$SkelPort = $Skel->{ 'port' };
			$SkelWire = $Skel->{ 'wire' };
			$Attr	  = $Skel->{ 'attr' };
			
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
			( $Wire->{ 'attr' }	& $ATTR_WEAK_W )
		){
			# List �� Weak �ǡ��������Τ� Hard �ʤΤ�����
			$Wire->{ 'width' } = $BitWidth;
			
			# list �� ATTR_WEAK_W °����ä�
			$Wire->{ 'attr' } &= ~$ATTR_WEAK_W;
			
		}elsif(
			( $Attr				& $ATTR_WEAK_W ) &&
			( $Wire->{ 'attr' }	& $ATTR_WEAK_W ) &&
			$Wire->{ 'width' } =~ /^\d/ && $BitWidth =~ /^\d/
		){
			# List���������� �Ȥ�� Weak �ʤΤǡ��礭���ۤ���Ȥ�
			
			( $MSB0, $LSB0 ) = GetBusWidth( $Wire->{ 'width' } );
			( $MSB1, $LSB1 ) = GetBusWidth( $BitWidth );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$Wire->{ 'width' } = $BitWidth = "$MSB0:$LSB0";
			
		}elsif(
			!( $Attr				& $ATTR_WEAK_W ) &&
			!( $Wire->{ 'attr' }	& $ATTR_WEAK_W ) &&
			$Wire->{ 'width' } =~ /^\d/ && $BitWidth =~ /^\d/
		){
			# ξ�� Hard �ʤΤǡ�����������äƤ���� size mismatch �ٹ�
			
			if( GetBusWidth2( $Wire->{ 'width' } ) != GetBusWidth2( $BitWidth )){
				Warning( "unmatch port width ( $ModuleName.$Name $BitWidth != $Wire->{ 'width' } )" );
			}
		}
		
		# ξ�� inout ���ʤ顤��Ͽ����ۤ��� REF ���ѹ�
		
		if( $Wire->{ 'attr' } & $Attr & $ATTR_INOUT ){
			$Attr |= $ATTR_REF;
		}
		
		# multiple driver �ٹ�
		
		if(
			( $Wire->{ 'attr' } & $Attr & $ATTR_FIX ) &&
			!( $Attr & $ATTR_MD )
		){
			Warning( "multiple driver ( wire : $Name )" );
		}
		
		$Wire->{ 'attr' } |= ( $Attr & ~$ATTR_WEAK_W );
		
	}else{
		# ������Ͽ
		
		push( @WireList, $Wire = {
			'name'	=> $Name,
			'width'	=> $BitWidth,
			'attr'	=> $Attr
		} );
		
		$WireList{ $Name } = $Wire;
	}
	
	# �ɥ饤�֤���Ƥ��� bit width ��׻�
	# input ����instance �ǸƤӽФ��� module �� output ����Ƥ���
	if( $Attr & ( $ATTR_IN | $ATTR_INOUT | $ATTR_FIX )){
		
		if( defined( $Wire->{ 'drive' } )){
			# ���Ǥ���������Ƥ���ۤ��ȡ��礭���ۤ�����
			( $MSB0, $LSB0 ) = GetBusWidth( $BitWidth );
			( $MSB1, $LSB1 ) = GetBusWidth( $Wire->{ 'drive' } );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$Wire->{ 'drive' } = $BitWidth = "$MSB0:$LSB0";
			
		}else{
			# ��ɥ饤�֤ʤΤǡ����Τޤ�����
			$Wire->{ 'drive' } = $BitWidth;
		}
	}
}

### query wire type & returns "in/out/inout" #################################
# $Mode eq "d" �� in/out/wire ���ʸ�⡼��

sub QueryWireType{
	
	my( $Wire, $Mode ) = @_;
	my( $Attr ) = $Wire->{ 'attr' };
	
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
		
		$Attr = $Wire->{ 'attr' };
		$Type = QueryWireType( $Wire, "" );
		
		$Type =	( $Type eq "input" )	? "I" :
				( $Type eq "output" )	? "O" :
				( $Type eq "inout" )	? "B" :
				( $Type eq "wire" )		? "W" :
										  "-" ;
		
		++$WireCntUnresolved if( !( $Attr & ( $ATTR_BYDIR | $ATTR_FIX | $ATTR_REF )));
		++$WireCntAdded		 if( !( $Attr & $ATTR_DEF ) && ( $Type =~ /[IOB]/ ));
		
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
			"\t$Wire->{ 'width' }\t$Wire->{ 'name' }\n"
		));
		
		# bus width == 'X' error
		Error( "Bus size is 'X' ( wire : $Wire->{ 'name' } )" )
			if( $Wire->{ 'width' } eq 'X' );
		
		# bus width is weakly defined error
		Warning( "Bus size is not fixed ( wire : $Wire->{ 'name' } )" )
			if(( $Wire->{ 'attr' } & (
				$ATTR_WEAK_W | $ATTR_DC_WEAK_W | $ATTR_DEF
			)) == $ATTR_WEAK_W );
	}
	
	@WireListBuf = sort( @WireListBuf );
	
	printf( "Wire info : Unresolved:%3d / Added:%3d ( $ModuleName\@$DefFile )\n",
		$WireCntUnresolved, $WireCntAdded );
	
	if( !open( fpList, ">> $ListFile" )){
		Error( "can't open file \"$ListFile\"" );
		return;
	}
	
	print( fpList "*** $ModuleName wire list ***\n" );
	print( fpList @WireListBuf );
	close( fpList );
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
		if( $Wire->{ 'name' } =~ /\$n/ && $Wire->{ 'width' } ne "" ){
			
			# Ÿ�����٤��Х�
			
			$Name		= $Wire->{ 'name' };
			$Attr		= $Wire->{ 'attr' };
			$BitWidth	= $Wire->{ 'width' };
			
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
			
			$Wire->{ 'attr' } |= ( $ATTR_REF | $ATTR_FIX );
		}
		
		$Wire->{ 'name' } =~ s/\$n//g;
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
	my( $BusWidth ) = @_;
	
	if( $BusWidth =~ /^(\d+):(\d+)$/ ){
		return( $1, $2 );
	}
	return( $BusWidth, 0 );
}

sub GetBusWidth2 {
	my( $MSB, $LSB ) = GetBusWidth( @_ );
	return( $MSB + 1 - $LSB );
}

### Format bus width #########################################################

sub FormatBusWidth {
	my( $_ ) = @_;
	
	if( /^\d+$/ ){
		return "[$_:0]";
	}elsif( /^\d/ ){
		return "[$_]";
	}else{
		return $_;
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
	my( $RewindPtr ) = tell( fpDef );
	my( $LineCnt ) = $.;
	my( $RepCnt );
	my( $VarName );
	
	my( $RepCntSt, $Step );
	
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
	$PrevRepCnt = $DefineTbl{ '__REP_CNT__' }{ 'macro' } if( defined( $DefineTbl{ '__REP_CNT__' } ));
	
	for(
		$RepCnt = $RepCntSt;
		( $RepCntSt < $RepCntEd ) ? $RepCnt < $RepCntEd : $RepCnt > $RepCntEd;
		$RepCnt += $Step
	){
		AddCppMacro( '__REP_CNT__', $RepCnt, undef, 1 );
		AddCppMacro( $VarName, $RepCnt, undef, 1 ) if( defined( $VarName ));
		
		seek( fpDef, $RewindPtr, $SEEK_SET );
		$. = $LineCnt;
		PrintRTL( sprintf( "# %d \"$DefFile\"\n", $. + 1 ));
		ExpandRepeatOutput( $BLKMODE_REPEAT );
	}
	
	if( defined( $PrevRepCnt )){
		AddCppMacro( '__REP_CNT__', $PrevRepCnt, undef, 1 );
	}else{
		delete( $DefineTbl{ '__REP_CNT__' } );
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
	$PerlBuf = EvaluateLine( $PerlBuf );
	
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
	
	PrintRTL( sprintf( "$_\n# %d \"$DefFile\"\n", $. + 1 ));
}

### enum state ###############################################################
# syntax:
#	enum [<type name>] { <n0> [, <n1> ...] } [<reg name> ];

sub Enumerate{
	
	my( $Line ) = @_;
	my( $Buf )  = $Line;
	my(
		$TypeName,
		@EnumList,
		$BitWidth,
		$i
	);
	
	# ; �ޤ� Buf ��ί�����
	
	if( $Line !~ /;/ ){
		while( $Line = <fpDef> ){
			$Buf .= $Line;
			last if( $Line =~ /;/ );
		}
	}
	
	# delete comment
	
	$Buf =~ s/\/\*.*?\*\///gs;
	$Buf =~ s/\x23.*//g;
	$Buf =~ s/\/\/.*//g;
	
	# delete \n
	
	$Buf =~ s/\n+/ /g;
	$Buf =~ s/\x0D//g;
	
	# compress blank
	
	$Buf =~ s/,/ /g;
	$Buf =~ s/;/ /g;
	$Buf =~ s/\s+/ /g;
	$Buf =~ s/ *(\W) */$1/g;
	$Buf =~ s/^ //g;
	$Buf =~ s/ $//g;
	
	#print( "enum>>$Buf\n" );
	
	# get typedef name
	
	if( $Buf =~ /(.+)({.*)/ ){
		$TypeName	= $1;
		$Buf		= $2;
	}
	
	# make enum list
	
	$Buf  =~ s/{(.*?)}(.*)/$2/g;
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
	
	# enum type list ����Ͽ
	$EnumListWidth{ $TypeName } = $i;
	
	# enum list �� define ����
	for( $i = 0; $i <= $#EnumList; ++$i ){
		PrintRTL( "\tparameter\t$EnumList[ $i ]\t= $BitWidth\'d$i;\n" );
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
		if( $Wire->{ 'name' } =~ /^$Param$/ && QueryWireType( $Wire, '' ) eq 'input' ){
			$_ .= $Tab . $Wire->{ 'name' } . ",\n";
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

### cpp directive # 0 "hogehoge" #############################################

sub CppDirectiveLine{
	
	my( $Line ) = @_;
	
	if( $Line =~ /^#\s*(\d+)\s+"(.*)"/ ){
		$. = $1 - 1;
		$DefFile = ( $2 eq "-" ) ? $ARGV[ 0 ] : $2;
	}
}

### CPP directive ���� #######################################################

sub AddCppMacro {
	my( $Name, $Macro, $Args, $bNoCheck ) = @_;
	
	$Macro	= '1' if( !defined( $Macro ));
	$Args	= 's' if( !defined( $Args ));
	
	if(
		( !defined( $bNoCheck ) || !$bNoCheck ) &&
		defined( $DefineTbl{ $Name } ) &&
		( $DefineTbl{ $Name }{ 'args' } ne $Args || $DefineTbl{ $Name }{ 'macro' } != $Macro )
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
	return Evaluate( ExpandMacro( $_ ));
}

### CPP �ޥ���Ÿ�� ###########################################################

sub ExpandMacro {
	local $_;
	my $Mode;
	
	( $_, $Mode ) = @_;
	
	my $Line;
	my $Line2;
	my $Name;
	my $bReplaced = 1;
	my( $ArgList, @ArgList );
	my $ArgNum;
	my $i;
	
	$Mode = $EXPAND_CPP | $EXPAND_REP if( !defined( $Mode ));
	
	if( $BlockRepeat && $Mode & $EXPAND_REP ){
		s/%(?:\{(.+?)\})?([+\-\d\.#]*[%cCdiouxXeEfgGnpsS])/ExpandPrintfFmtSub( $2, $1 )/ge;
	}
	
	while( $bReplaced ){
		$bReplaced = 0;
		$Line = '';
		
		if( $Mode & $EXPAND_CPP ){
			while( /\b($CSymbol)\b(.*)/s ){
				$Line .= $`;
				( $Name, $_ ) = ( $1, $2 );
				
				if( $Name eq '__FILE__' ){
					$Line .= $DefFile;
				}elsif( $Name eq '__LINE__' ){
					$Line .= $.;
				}elsif( !defined( $DefineTbl{ $Name } )){
					# �ޥ���ǤϤʤ�
					$Line .= $Name;
				}elsif( $DefineTbl{ $Name }{ 'args' } eq 's' ){
					# ñ��ޥ���
					$Line .= $DefineTbl{ $Name }{ 'macro' };
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
						while( 1 ){
							s#[\t ]*/\*.*?\*/[\t ]*# #gs;
							s#[\t ]*//.*$##gm;
							last if( /^$OpenClose/ );
							if( !( $Line2 = <fpDef> )){
								Error( "unmatched function macro ')': $Name" );
								$Line .= $Name;
								last;
							};
							$_ .= $Line2;
						}
						
						# �ޥ����������
						if( /^($OpenClose)(.*)/s ){
							( $ArgList, $_ ) = ( $1, $2 );
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
								$ArgNum = $DefineTbl{ $Name }{ 'args' };
								$ArgNum = -$ArgNum - 1 if( $ArgNum < 0 );
								
								if( !(
									$DefineTbl{ $Name }{ 'args' } >= 0 ?
										( $ArgNum == $#ArgList + 1 ) : ( $ArgNum <= $#ArgList + 1 )
								)){
									Error( "invalid number of macro arg: $Name" );
									$Line .= $Name . '()';
								}else{
									# ��������°������ִ�
									$Line2 = $DefineTbl{ $Name }{ 'macro' };
									for( $i = 0; $i < $ArgNum; ++$i ){
										$Line2 =~ s/\b__\$ARG_${i}\$__\b/$ArgList[ $i ]/g;
									}
									
									# ���Ѱ������ִ�
									if( $DefineTbl{ $Name }{ 'args' } < 0 ){
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
	}
	
	if( $Mode & $EXPAND_EVAL ){
		# sizeof Ÿ��
		s/\bsizeof($OpenClose)/SizeOf( $1 )/ge;
		
		# typeof Ÿ��
		s/\btypeof($OpenClose)/TypeOf( $1 )/ge;
		
		# Eval Ÿ��
		s/\$Eval($OpenClose)/Evaluate($1)/ge;
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
	return( sprintf( "%$Fmt", $DefineTbl{ $Name }{ 'macro' } ));
}

### sizeof / typeof ##########################################################

sub SizeOf {
	local( $_ ) = @_;
	my $Wire = 0;
	my $Bits = 0;
	
	while( s/($CSymbol)// ){
		if( !defined( $Wire = $WireList{ $1 } )){
			Error( "undefined wire '$1'" );
		}elsif( $Wire->{ 'width' } =~ /(\d+):(\d+)/ ){
			$Bits += ( $1 - $2 + 1 );
		}else{
			++$Bits;
		}
	}
	$Bits;
}

sub TypeOf {
	local( $_ ) = @_;
	
	if( !/($CSymbol)/ ){
		Error( "syntax error (typeof)" );
		$_ = '';
	}elsif( !defined( $_ = $WireList{ $1 } )){
		Error( "undefined wire '$1'" );
		$_ = '';
	}else{
		$_ = $_->{ 'width' } eq '' ? '' : "[$_->{ 'width' }]";
	}
	$_;
}

### �ե����� include #########################################################

sub Include {
	local( $_ ) = @_;
	
	my $RewindPtr	= tell( fpDef );
	my $LineCnt		= $.;
	my $PrevDefFile	= $DefFile;
	
	close( fpDef );
	
	if( !open( fpDef, "< $_" )){
		Error( "can't open include file '$_'" );
	}else{
		$DefFile = $_;
		PrintRTL( "# 1 \"$_\"\n" );
		print( "including file '$_'...\n" ) if( $Debug );
		ExpandRepeatOutput();
		print( "back to file '$PrevDefFile'...\n" ) if( $Debug );
	}
	$DefFile = $PrevDefFile;
	open( fpDef, "< $DefFile" );
	
	seek( fpDef, $RewindPtr, $SEEK_SET );
	$. = $LineCnt;
	PrintRTL( sprintf( "# %d \"$DefFile\"\n", $. + 1 ));
}
