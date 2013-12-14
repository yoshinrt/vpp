#!/usr/bin/perl -w

##############################################################################
#
#		vpp -- verilog preprocessor		Ver.2.00
#		Copyright(C) by DDS
#
##############################################################################
#
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
my $ATTR_REG		= ( $enum <<= 1 );		# outreg / ioreg ( Add repo ���� )
my $ATTR_MD			= ( $enum <<= 1 );		# multiple drv ( �ٹ����� )
my $ATTR_NP			= ( $enum <<= 1 );		# print ���� ( .def �ǥݡ�������Ѥ� )
my $ATTR_DC_WEAK_W	= ( $enum <<= 1 );		# Bus Size �ϼ��ο���ٹ������
my $ATTR_WEAK_W		= ( $enum <<= 1 );		# Bus Size �ϼ��ο���
my $ATTR_NC			= 0xFFFFFFFF;

my $CSymbol		= '\b[_a-zA-Z]\w*\b';
#$DefSkelPort	= "[io]?(.*)";
my $DefSkelPort	= "(.*)";
my $DefSkelWire	= "\$1";
my $UnknownBusType	= '\[X[^\]]*\]';

my $tab0 = 8;
my $tab1 = 28;
my $tab2 = 52;

my $ErrorCnt = 0;
my $TabWidth = 4;	# ������

my $TabWidthType	= 8;	# input / output ��
my $TabWidthBit		= 8;	# [xx:xx]

my $OpenClose;
$OpenClose			= qr/\([^()]*(?:(??{$OpenClose})[^()]*)*\)/;
my $OpenCloseArg	= qr/[^(),]*(?:(??{$OpenClose})[^(),]*)*/;
my $Debug	= 0;

my $MODMODE_NORMAL	= 0;
my $MODMODE_TEST	= 1 << 0;
my $MODMODE_INC		= 1 << 1;
my $MODMODE_TESTINC	= $MODMODE_TEST | $MODMODE_INC;

my $SEEK_SET = 0;
my $bPrintRTL_Enable	= 1;

my( $DefFile, $RTLFile, $ListFile, $CppFile, $VppFile );
my $bInModule;
my $bAutoFix;
my $bParsing;
my $bPostProcess;
my $RTLBuf;
my $ModuleName;
my $ExpandTab;

# ����ơ��֥�ط�
my @WireListName;
my @WireListAttr;
my @WireListWidth;
my $WireListCnt;
my $iModuleMode;
my $PortList;
my $PortDef;
my @EnumListWidth;
my %DefineTbl;
my $SkelListCnt;
my @WireListWidthDrv;
my @SkelListAttr;
my @SkelListWire;
my @SkelListPort;
my @SkelListUsed;
my %EnumListWidth;

main();
exit( $ErrorCnt != 0 );

### main procedure ###########################################################

sub main{
	local( $_ );
	my(
		$Line,
		$Line2,
		$Word,
	);
	
	if( $#ARGV < 0 ){
		print( "usage: vpp.pl <Def file>\n" );
		return;
	}
	
	# vpp.pl �¹� dir ������ perlpp ��
	
	my $VppDir = $0;
	$VppDir =~ s|\\|/|g;
	
	$VppDir = ( $VppDir =~ /(.*\/)/ ) ? $1 : "";
	
	# -DMACRO setup
	my $CppMacroDef = '';
	
	while( 1 ){
		$_ = $ARGV[ 0 ];
		
		$CppMacroDef .= " $_" if( /^-[vID]/ );
		
		if    ( /^-v/		){ $Debug = 1;
		}elsif( /^-I(.*)/	){ push( @INC, $1 );
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
	$CppFile  = "$1.cpp$3";
	$VppFile  = "$1.vpp$3";
	
	unlink( $ListFile );
	
	# expand $repeat
	if( !open( fpDef, "< $DefFile" )){
		Error( "can't open file \"$DefFile\"" );
		return;
	}
	
	open( fpRTL, "> $CppFile" );
	
	ExpandRepeatParser();
	
	close( fpRTL );
	close( fpDef );
	
	system( "cp $CppFile stage2" ) if( $Debug );
	
	# vpp
	if( !open( fpDef, "< $CppFile" )){
		Error( "can't open file \"$CppFile\"" );
		return;
	}
	
	$ExpandTab ?
		open( fpRTL, "| expand -$TabWidth > $VppFile" ) :
		open( fpRTL, "> $VppFile" );
	
	$bParsing = 1;
	MultiLineParser( $Line );
	
	close( fpRTL );
	close( fpDef );
	
	unlink( $CppFile );
	
	if( $bPostProcess ){
		system( "cp $VppFile stage3" ) if( $Debug );
		
		# �ٱ�Х������������ �Х�����������
		open( fpIn, "<$VppFile" );
		open( fpOut, ">$CppFile" );
		
		OutputBusTypeDef( fpOut );
		while( <fpIn> ){
			print( fpOut );
		}
		
		close( fpIn );
		close( fpOut );
		
		system( "cp $CppFile stage4" ) if( $Debug );
		
		#########
		
		
		## VPreProcessor( $CppFile, $RTLFile, '-nl' . $CppMacroDef );
		unlink( $VppFile );
		unlink( $CppFile );
	}else{
		rename( $VppFile, $RTLFile );
	}
	
	if( $ErrorCnt ){
		#unlink( $RTLFile );
	}
}

sub OutputBusTypeDef{
	
	my( $fp ) = @_;
	my(
		$BusType,
		$BusSize,
		$i,
	);
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		
		if( $WireListWidth[ $i ] =~ /(\d+):(\d+)/ ){
			$BusSize = $1 - $2 + 1;
			$BusType = '[' . $WireListWidth[ $i ] . ']';
		}else{
			if(
				( $BusSize = $WireListWidth[ $i ] ) eq '' ||
				$BusSize =~ /^X/ ||
				$BusSize =~ /^0\?/
			){
				$BusSize = 1;
			}
			$BusType = "[" . ( $BusSize - 1 ) . ":0]";
		}
		
		print( $fp "#define SIZEOF_$WireListName[$i] $BusSize\n" );
		print( $fp "#define TYPEOF_$WireListName[$i] $BusType\n" );
	}
}

### �ޥ���饤��ѡ��� #######################################################

sub MultiLineParser {
	local( $_ );
	my( $Line, $Word );
	
	while( <fpDef> ){
		( $Word, $Line ) = GetWord( $_ );
		
		if    ( $_ =~ /^#/			){ CppDirectiveLine( $_ );
		}elsif( $Word eq 'module'		){ StartModule( $Line );
		}elsif( $Word eq 'module_inc'	){ StartModule( $Line ); $iModuleMode = $MODMODE_INC;
		}elsif( $Word eq 'endmodule'	){ EndModule( $_ );
		}elsif( $Word eq 'instance'		){ DefineInst( $Line );
		}elsif( $Word eq 'enum'			){ Enumerate( $Line );
		}elsif( $Word eq '$file'		){ DefineFileName( $Line );
		}elsif( $Word eq '$wire'		){ DefineDefWireSkel( $Line );
		}elsif( $Word eq '$header'		){ OutputHeader();
		}elsif( $Word eq 'testmodule'	){ StartModule( $Line ); $iModuleMode = $MODMODE_TEST;
		}elsif( $Word eq 'testmodule_inc'){ StartModule( $Line ); $iModuleMode = $MODMODE_TESTINC;
		}elsif( $Word eq '$AllInputs'	){ PrintAllInputs( $Line, $_ );
		}elsif( $Word eq '$AutoFix'		){ $bAutoFix = ( $Line =~ /\bon\b/ );
		}elsif( $Word eq '$SetBusSize'	){ SetBusSize( $_ );
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

my( %RepeatVarTbl );

sub ExpandRepeatParser {
	my( $bOutput, $bRepeating, $RepCnt ) = @_;
	$bOutput	= 1 if( !defined( $bOutput ));
	$bRepeating	= 0 if( !defined( $bRepeating ));
	
	local( $_ );
	my $Line;
	my $i;
	
	while( <fpDef> ){
		if( /^\s*#/	){
			# \ �ǽ���äƤ���Ԥ�Ϣ��
			while( /\\$/ ){
				if( !( $Line = <fpDef> )){
					last;
				}
				$_ .= $Line;
			}
			
			# ����������
			s#[\t ]*/\*.*?\*/[\t ]*# #gs;
			s#[\t ]*//.*$##gm;
			
			# \ ���
			s/[\t ]*\\[\x0D\x0A]+[\t ]*/ /g;
			s/\s+$//g;
			s/^\s*#\s*//;
			
			# $DefineTbl{ $1 }->[ 0 ]:  >=0: ����  <0: ���Ѱ���  's': ñ��ޥ���
			# $DefineTbl{ $1 }->[ 1 ]:  �ޥ����������
			
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
				undef( $DefineTbl{ $1 } );
			}elsif( /^ifdef\b/ ){
			}elsif( /^ifndef\b/ ){
			}elsif( /^if\b/ ){
			}elsif( /^elif\b/ ){
			}elsif( /^else\b/ ){
			}elsif( /^endif\b/ ){
			}elsif( /^repeat\s*($OpenClose)/	){ RepeatOutput( $1 );
			}elsif( /^endrep\b/					){ return;
			}elsif( /^perl\s+(.*)/s				){ ExecPerl( $1 );
			}elsif( /^require\s+(.*)/			){ Require( $1 );
			}else								 {
				/(\S+)/;
				Error( "unknown cpp directive '$1'" );
			}
		}else{
			$_ = ExpandMacro( $_ );
			
			$_ = ExpandPrintfFmt( $_, $RepCnt ) if( $bRepeating );
			PrintRTL( $_ );
		}
	}
}

sub ExpandPrintfFmtSub {
	my( $Fmt, $Num, $Name ) = @_;
	
	$Num = $RepeatVarTbl{ $Name } if( defined( $Name ));
	return( sprintf( "%$Fmt", $Num ));
}

sub ExpandPrintfFmt {
	local $_;
	my $Num;
	
	( $_, $Num ) = @_;
	s/%(?:\{(.+?)\})?([+\-\d\.#]*[%cCdiouxXeEfgGnpsS])/ExpandPrintfFmtSub( $2, $Num, $1 )/ge;
	return( $_ );
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
	
	@WireListName	= ();
	@WireListAttr	= ();
	@WireListWidth	= ();
	undef( @WireListWidthDrv );
	$WireListCnt	= 0;
	$iModuleMode	= $MODMODE_NORMAL;
	$PortList		= ();
	$PortDef		= ();
	
	@EnumListWidth	= ();
	
	$bInModule	= 1;
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
			
			$Attr = ( $InOut eq "input" )	? ( $ATTR_NP | $ATTR_IN )	:
					( $InOut eq "output" )	? ( $ATTR_NP | $ATTR_OUT )	:
					( $InOut eq "inout" )	? ( $ATTR_NP | $ATTR_INOUT ):
					( $InOut eq "wire" )	? ( $ATTR_NP | $ATTR_WIRE )	:
					( $InOut eq "reg" )		? ( $ATTR_NP | $ATTR_WIRE | $ATTR_REF )	:
					( $InOut eq "outreg" )	? ( $ATTR_OUT  | $ATTR_REG ):
					( $InOut eq "ioreg" )	? ( $ATTR_INOUT| $ATTR_REG ):
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
		$i
	);
	
	my( $MSB, $LSB, $MSB_Drv, $LSB_Drv );
	
	# expand bus
	
	ExpandBus();
	
	PrintRTL( '//' ) if( $iModuleMode & $MODMODE_INC );
	PrintRTL( $Line );
	$bInModule = 0;
	
	# module port �ꥹ�Ȥ����
	
	#SortPort();
	
	$bFirst = 1;
	PrintRTL( '//' ) if( $iModuleMode & $MODMODE_INC );
	PrintRTL( "module $ModuleName" );
	
	if( $iModuleMode == $MODMODE_NORMAL ){
		
		my $bCLikePortDef = $PortList ne "";
		
		for( $i = 0; $i < $WireListCnt; ++$i ){
			
			$Type = QueryWireType( $i, $bCLikePortDef ? 'd' : '' );
			
			if( $Type eq "input" || $Type eq "output" || $Type eq "inout" ){
				#PrintRTL( "\t$WireListName[ $i ],\n" );
				$PortList .= "\t$WireListName[ $i ],\n";
			}
		}
		
		if( $PortList ){
			$PortList =~ s/,([^,]*)$/$1/;
			PrintRTL( "(\n$PortList)" );
		}
		
	}
	
	PrintRTL( ";\n$PortDef" );
	
	# in/out/reg/wire �������
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		if(( $Type = QueryWireType( $i, "d" )) ne "" ){
			
			if( $iModuleMode & $MODMODE_TEST ){
				$Type = "reg"  if( $Type eq "input" );
				$Type = "wire" if( $Type eq "output" || $Type eq "inout" );
			}elsif( $iModuleMode & $MODMODE_INC ){
				# ��ƥ��ȥ⥸�塼��� include �⡼�ɤǤϡ��Ȥꤢ�������� wire �ˤ���
				$Type = 'wire';
			}
			
			PrintRTL( TabSpace( $Type, $TabWidthType, $TabWidth ));
			
			if( $WireListWidth[ $i ] eq "" ){
				# bit ����ʤ�
				PrintRTL( TabSpace( '', $TabWidthBit, $TabWidth ));
			}else{
				# 10:2 �Ȥ�
				PrintRTL( TabSpace( FormatBusWidth( $WireListWidth[ $i ] ), $TabWidthBit, $TabWidth ));
			}
			
			PrintRTL( "$WireListName[ $i ];\n" );
		}
	}
	
	# Hi-Z autofix
	
	if( $bAutoFix ){
		for( $i = 0; $i < $WireListCnt; ++$i ){
			
			( $MSB,	$LSB ) = GetBusWidth( $WireListWidth[ $i ] );
			
			if( defined( $WireListWidthDrv[ $i ] )){
				( $MSB_Drv, $LSB_Drv ) = GetBusWidth( $WireListWidthDrv[ $i ] );
				
				# ��ʬ��������Ƥ���
				if( $MSB > $MSB_Drv ){
					PrintRTL( sprintf( "\tassign %s[%d:%d]\t= %d'd0;\n",
						$WireListName[$i], $MSB, $MSB_Drv + 1, $MSB - $MSB_Drv
					));
				}elsif( $LSB < $LSB_Drv ){
					PrintRTL( sprintf( "\tassign %s[%d:%d]\t= %d'd0;\n",
						$WireListName[$i], $LSB_Drv - 1, $LSB_Drv, $LSB_Drv - $LSB
					));
				}
			}else{
				# ��������Ƥ��ʤ�
				PrintRTL( sprintf( "\tassign $WireListName[$i]\t= %d'd0;\n", $MSB - $LSB + 1 ));
			}
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
	return if( !$bPrintRTL_Enable );
	
	s/\$Eval($OpenClose)/Evaluate($1)/ge;
	
	# (in|out)put  [X] hoge�� ����
	if( $bParsing ){
		if( /$UnknownBusType/ ){
			s/$UnknownBusType(\s+)($CSymbol)/TYPEOF_$2$1$2/g;
			
			$bPostProcess = 1;
		}
		
		s/\bsizeof\s*\(\s*($CSymbol)\s*\)/SIZEOF_$1/g;
		s/\btypeof\s*\(\s*($CSymbol)\s*\)/TYPEOF_$1/g;
	}
	
	# outreg / ioreg ����
	
	if( /\b(out|io)reg\b/ ){
		$tmp = $_;
		
		s/\boutreg\b/output/g || s/\bioreg\b/inout/g;
		$tmp =~ s/\b(out|io)reg\b/reg\t/g;
		
		$_ .= $tmp;
	}
	
	# Case / FullCase ����
	
	s|\bC(asex?\s*\(.*\))|c$1 /* synopsys parallel_case */|g;
	s|\bFullC(asex?\s*\(.*\))|c$1 /* synopsys parallel_case full_case */|g;
	
	if( $bInModule ){
		$RTLBuf .= $_;
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
	
	@SkelListPort = ();
	@SkelListWire = ();
	@SkelListAttr = ();
	@SkelListUsed = ();
	$SkelListCnt  = 0;
	
	if( $Line !~ /\s+([\w\d]+)(\s+#\([^\)]+\))?\s+(\S+)\s+"?(\S+)"?\s*([\(;])/ ){
#	if( $Line !~ /\s*,?\s*([\w\d]+)(\s+#\([^\)]+\))?\s*,?\s*(\S+)\s*,?\s*"?(\S+)"?\s*,?\s*([\(;])/ ){
		Error( "syntax error" );
		return;
	}
	
	# get module name, module inst name, module file
	
	my( $ModuleName, $ModuleParam, $ModuleInst, $ModuleFile ) = ( $1, $2, $3, $4 );
	
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
			
			if( $bAutoFix && $BitWidthWire ne '' && $Wire =~ /^$CSymbol$/ ){
				$tmp2 = FormatBusWidth( $BitWidthWire );
				$Len += length( $tmp2 );
				$tmp .= $tmp2;
			}
			
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
	
	WarnUnusedSkelList( $ModuleInst );
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
		Error( "can't find module \"$ModuleName@$ModuleFile\"" );
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
	
	if( !/^\s*([\w\d\$]+)(.*)/ ){
		/^\s*(.)(.*)/;
	}
	
	return( $1, $2 );
}

### print error msg ##########################################################

sub Error{
	local( $_ ) = @_;
	printf( "$DefFile(%d): $_\n", $. );
	++$ErrorCnt;
}

sub Warning{
	local( $_ ) = @_;
	printf( "$DefFile(%d): Warning: $_\n", $. );
}

### define output file name ##################################################

sub DefineFileName{
	( $RTLFile ) = @_;
	$RTLFile =~ s/\s*(\S*)/$1/g;
}

### define default port --> wire name ########################################

sub DefineDefWireSkel{
	local( $_ ) = @_;
	
	if( /\s*(\S+)\s+(\S+)/ ){
		$DefSkelPort = $1;
		$DefSkelWire = $2;
	}else{
		Error( "syntax error" );
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
		$Attr
	);
	
	while( $Line = <fpDef> ){
		$Line =~ s/\/\/.*//g;
		next if( $Line =~ /^\s*$/ );
		last if( $Line =~ /^\s*\);/ );
		
		$Line =~ /^\s*(\S+)\s*(\S+)?\s*(\S+)?/;
		
		$Port = $1;
		$Wire = $2;
		$Attr = $3;
		
		if( $Wire =~ /^[MBU]?(?:NP|NC|W|I|O|IO|U)$/ ){
			$Attr = $Wire;
			$Wire = "";
		}
		
		$SkelListAttr[ $SkelListCnt ] = 0;
		
		# attr
		
		$SkelListAttr[ $SkelListCnt ] = $ATTR_MD		if( $Attr =~ /M/ );
		$SkelListAttr[ $SkelListCnt ] = $ATTR_DC_WEAK_W	if( $Attr =~ /B/ );
		$SkelListUsed[ $SkelListCnt ] = 1				if( $Attr =~ /U/ );
		
		$SkelListPort[ $SkelListCnt ] = $Port;
		$SkelListWire[ $SkelListCnt ] = $Wire;
		
		$SkelListAttr[ $SkelListCnt ] |=
			( $Attr =~ /NP$/ ) ? $ATTR_NP	:
			( $Attr =~ /NC$/ ) ? $ATTR_NC	:
			( $Attr =~ /W$/  ) ? $ATTR_WIRE	:
			( $Attr =~ /I$/  ) ? $ATTR_IN	:
			( $Attr =~ /O$/  ) ? $ATTR_OUT	:
			( $Attr =~ /IO$/ ) ? $ATTR_INOUT	:
								0;
		
		++$SkelListCnt;
	}
}

### tmpl list ̤���ѷٹ� #####################################################

sub WarnUnusedSkelList{
	
	local( $_ ) = @_;
	my( $i );
	
	for( $i = 0; $i < $SkelListCnt; ++$i ){
		if( $SkelListUsed[ $i ] != 1 ){
			Warning( "tmpl isn't used ( $SkelListPort[ $i ] --> $SkelListWire[ $i ] \@ $_ )" );
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
		
		$i
	);
	
	for( $i = 0; $i < $SkelListCnt; ++$i ){
		# bit���� 0 �ʤΤ� SkelWire �� $n �����ä��顤
		# ����Ū�� hit �����ʤ�
		next if( $BitWidth == 0 && $SkelListWire[ $i ] =~ /\$n/ );
		
		# Hit ����
		last if( $Port =~ /^$SkelListPort[ $i ]$/ );
	}
	
	# find/and create wire name
	
	if( $i < $SkelListCnt ){
		
		# port tmpl ���Ѥ��줿
		$SkelListUsed[ $i ] = 1;
		
		$SkelPort = $SkelListPort[ $i ];
		$SkelWire = $SkelListWire[ $i ];
		$Attr	  = $SkelListAttr[ $i ];
		
		# NC �ʤ�ꥹ�Ȥ���ʤ�
		
		if( $Attr == $ATTR_NC ){
			return( "", $Attr );
		}
		
	}else{
		
		$SkelPort = $DefSkelPort;
		$SkelWire = $DefSkelWire;
		$Attr	  = 0;
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

### wire �� search ###########################################################

sub SearchWire{
	
	my( $Wire ) = @_;
	my(
		$i,
		$WireBus
	);
	
	$Wire =~ s/\$n//g;
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		$WireBus = $WireListName[ $i ];
		$WireBus =~ s/\$n//g;
		
		return( $i ) if( $Wire eq $WireBus );
	}
	
	return( -1 );
}

### wire ����Ͽ ##############################################################

sub RegisterWire{
	
	my( $Wire, $BitWidth, $Attr, $ModuleName ) = @_;
	my(
		$i
	);
	
	my( $MSB0, $MSB1, $LSB0, $LSB1 );
	
	if(( $i = SearchWire( $Wire )) >= 0 ){
		# ���Ǥ���Ͽ�Ѥ�
		
		# ATTR_WEAK_W �������� BitWidth �򹹿�����
		if(
			!( $Attr				& $ATTR_WEAK_W ) &&
			( $WireListAttr[ $i ]	& $ATTR_WEAK_W )
		){
			# List �� Weak �ǡ��������Τ� Hard �ʤΤ�����
			$WireListWidth[ $i ] = $BitWidth;
			
			# list �� ATTR_WEAK_W °����ä�
			$WireListAttr[ $i ] &= ~$ATTR_WEAK_W;
			
		}elsif(
			( $Attr					& $ATTR_WEAK_W ) &&
			( $WireListAttr[ $i ]	& $ATTR_WEAK_W ) &&
			$WireListWidth[ $i ] =~ /^\d/ && $BitWidth =~ /^\d/
		){
			# List���������� �Ȥ�� Weak �ʤΤǡ��礭���ۤ���Ȥ�
			
			( $MSB0, $LSB0 ) = GetBusWidth( $WireListWidth[ $i ] );
			( $MSB1, $LSB1 ) = GetBusWidth( $BitWidth );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$WireListWidth[ $i ] = $BitWidth = "$MSB0:$LSB0";
			
		}elsif(
			!( $Attr				& $ATTR_WEAK_W ) &&
			!( $WireListAttr[ $i ]	& $ATTR_WEAK_W ) &&
			$WireListWidth[ $i ] =~ /^\d/ && $BitWidth =~ /^\d/
		){
			# ξ�� Hard �ʤΤǡ�����������äƤ���� size mismatch �ٹ�
			
			if( GetBusWidth2( $WireListWidth[ $i ] ) != GetBusWidth2( $BitWidth )){
				Warning( "unmatch port width ( $ModuleName.$Wire $BitWidth != $WireListWidth[ $i ] )" );
			}
		}
		
		# ξ�� inout ���ʤ顤��Ͽ����ۤ��� REF ���ѹ�
		
		if( $WireListAttr[ $i ] & $Attr & $ATTR_INOUT ){
			$Attr |= $ATTR_REF;
		}
		
		# multiple driver �ٹ�
		
		if(
			( $WireListAttr[ $i ] & $Attr & $ATTR_FIX ) &&
			!( $Attr & $ATTR_MD )
		){
			Warning( "multiple driver ( wire : $Wire )" );
		}
		
		$WireListAttr[ $i ] |= ( $Attr & ~$ATTR_WEAK_W );
		
	}else{
		# ������Ͽ
		$i = $WireListCnt;
		
		$WireListName [ $WireListCnt ] = $Wire;
		$WireListWidth[ $WireListCnt ] = $BitWidth;
		$WireListAttr [ $WireListCnt ] = $Attr;
		
		++$WireListCnt;
	}
	
	# �ɥ饤�֤���Ƥ��� bit width ��׻�
	# input ����instance �ǸƤӽФ��� module �� output ����Ƥ���
	if( $Attr & ( $ATTR_IN | $ATTR_INOUT | $ATTR_FIX )){
		
		if( defined( $WireListWidthDrv[ $i ] )){
			# ���Ǥ���������Ƥ���ۤ��ȡ��礭���ۤ�����
			( $MSB0, $LSB0 ) = GetBusWidth( $BitWidth );
			( $MSB1, $LSB1 ) = GetBusWidth( $WireListWidthDrv[ $i ] );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$WireListWidthDrv[ $i ] = $BitWidth = "$MSB0:$LSB0";
			
		}else{
			# ��ɥ饤�֤ʤΤǡ����Τޤ�����
			$WireListWidthDrv[ $i ] = $BitWidth;
		}
	}
}


### query wire type & returns "in/out/inout" #################################
# $Mode eq "d" �� in/out/wire ���ʸ�⡼��

sub QueryWireType{
	
	my( $i, $Mode ) = @_;
	
	my( $Attr ) = $WireListAttr[ $i ];
	
	return( ''		 ) if( $Attr & $ATTR_NP  && $Mode eq 'd' );
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
		$i,
	);
	
	$WireCntUnresolved = 0;
	$WireCntAdded	   = 0;
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		
		$Attr = $WireListAttr[ $i ];
		$Type = QueryWireType( $i, "" );
		
		$Type =	( $Type eq "input" )	? "I" :
				( $Type eq "output" )	? "O" :
				( $Type eq "inout" )	? "B" :
				( $Type eq "wire" )		? "W" :
										  "-" ;
		
		++$WireCntUnresolved if( !( $Attr & ( $ATTR_BYDIR | $ATTR_FIX | $ATTR_REF )));
		#++$WireCntAdded		 if( !( $Attr & $ATTR_NP ) && !( $Attr & $ATTR_REG ) && ( $Type =~ /[IOB]/ ));
		++$WireCntAdded		 if( !( $Attr & ( $ATTR_NP | $ATTR_REG | $ATTR_IN | $ATTR_OUT | $ATTR_INOUT )) && ( $Type =~ /[IOB]/ ));
		
		push( @WireListBuf, (
			$Type .
			(( $Attr & ( $ATTR_BYDIR | $ATTR_FIX | $ATTR_REF ))
										? "-" : "!" ) .
			(	( $Attr & $ATTR_NP )	? "d" :
				( $Attr & $ATTR_REG )	? "r" : "-" ) .
			(( $Attr & $ATTR_WIRE )		? "W" : "-" ) .
			(( $Attr & $ATTR_INOUT )	? "B" : "-" ) .
			(( $Attr & $ATTR_OUT )		? "O" : "-" ) .
			(( $Attr & $ATTR_IN )		? "I" : "-" ) .
			(( $Attr & $ATTR_BYDIR )	? "B" : "-" ) .
			(( $Attr & $ATTR_FIX )		? "F" : "-" ) .
			(( $Attr & $ATTR_REF )		? "R" : "-" ) .
			"\t$WireListWidth[ $i ]\t$WireListName[ $i ]\n"
		));
		
		# bus width == 'X' error
		Error( "Bus size is 'X' ( wire : $WireListName[ $i ] )" )
			if( $WireListWidth[ $i ] eq 'X' );
		
		# bus width is weakly defined error
		Warning( "Bus size is not fixed ( wire : $WireListName[ $i ] )" )
			if(( $WireListAttr[ $i ] & (
				$ATTR_WEAK_W | $ATTR_DC_WEAK_W | $ATTR_NP
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
	
	my( $i );
	my(
		$Wire,
		$Attr,
		$BitWidth,
		$WireCnt
	);
	
	$WireCnt = $WireListCnt;
	
	for( $i = 0; $i < $WireCnt; ++$i ){
		if( $WireListName[ $i ] =~ /\$n/ && $WireListWidth[ $i ] ne "" ){
			
			# Ÿ�����٤��Х�
			
			$Wire		= $WireListName[ $i ];
			$Attr		= $WireListAttr[ $i ];
			$BitWidth	= $WireListWidth[ $i ];
			
			# FR wire �ʤ� F �Ȥߤʤ�
			
			if(( $Attr & ( $ATTR_FIX | $ATTR_REF )) == ( $ATTR_FIX | $ATTR_REF )){
				$Attr &= ~$ATTR_REF
			}
			
			if( $Attr & ( $ATTR_REF | $ATTR_BYDIR )){
				ExpandBus2( $Wire, $BitWidth, $Attr, 'ref' );
			}
			
			if( $Attr & ( $ATTR_FIX | $ATTR_BYDIR )){
				ExpandBus2( $Wire, $BitWidth, $Attr, 'fix' );
			}
			
			# List ����ν���
			
			$WireListAttr[ $i ] |= ( $ATTR_REF | $ATTR_FIX );
		}
		
		$WireListName[ $i ] =~ s/\$n//g;
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

### sort bus #################################################################

sub SortPort {
	
	my( $i, @WireList, $_ );
	
	@WireList = ();
	
	# �磻�䡼̾��°����ҤȤĤ�����ˤޤȤ��
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		push( @WireList,
			( QueryWireType( $i, '' ) eq 'wire' ? "\xFF" : '' ) .
			"$WireListName[$i]\t$WireListAttr[$i]\t$WireListWidth[$i]"
		);
	}
	
	# ������
	@WireList = sort( @WireList );
	
	# ������˽��᤹
	for( $i = 0; $i < $WireListCnt; ++$i ){
		$WireList[ $i ] =~ /\xFF?(.*)/;
		
		( $WireListName[ $i ], $WireListAttr[ $i ], $WireListWidth[ $i ] ) =
			split( /\t/, $1 );
	}
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
	my( $RepCntEd ) = @_;
	my( $RewindPtr ) = tell( fpDef );
	my( $LineCnt ) = $.;
	my( $bPrintEnb ) = $bPrintRTL_Enable;
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
		$RepCntEd = $RepCntSt + 1;
		$Step = 1;
		$bPrintRTL_Enable = 0;
	}
	
	for(
		$RepCnt = $RepCntSt;
		( $RepCntSt < $RepCntEd ) ? $RepCnt < $RepCntEd : $RepCnt > $RepCntEd;
		$RepCnt += $Step
	){
		$RepeatVarTbl{ $VarName } = $RepCnt if( defined( $VarName ));
		seek( fpDef, $RewindPtr, $SEEK_SET );
		$. = $LineCnt;
		ExpandRepeatParser( 1, 1, $RepCnt );
	}
	
	$bPrintRTL_Enable = $bPrintEnb;
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
	my( $EofStr ) = @_;
	my( $PerlCode );
	
	$EofStr =~ s/^\s*(\S+)/$1/;
	
	while( <fpDef> ){
		last if( /^\s*$EofStr$/ );
#		s/#.*//;
		$PerlCode .= $_;
	}
	
#	$PerlCode =~ s/\$Eval\s*\(/(/g;
	$PerlCode = EvaluateLine( $PerlCode );
	
	if( $Debug ){
		print( "\n=========== perl code =============\n" );
		print( $PerlCode );
		print( "\n===================================\n" );
	}
	$_ = ();
	$_ = eval( $PerlCode );
	Error( $@ ) if( $@ ne '' );
	if( $Debug ){
		print( "\n=========== output code =============\n" );
		print( $_ );
		print( "\n===================================\n" );
	}
	PrintRTL( $_ );
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
	
	# post preprocess �׵�
	
	$bPostProcess = 1;
	
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
		PrintRTL( "#define $TypeName\t[$i:0]\n" );
		PrintRTL( "#define ${TypeName}_w\t$BitWidth\n" );
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
	my( $Cnt );
	
	$Param	=~ s/^\s*(\S+).*/$1/;
	$Tab	=~ /^(\s*)/; $Tab = $1;
	$_		= ();
	
	for( $Cnt = 0; $Cnt < $WireListCnt; ++$Cnt ){
		if( $WireListName[ $Cnt ] =~ /^$Param$/ && QueryWireType( $Cnt, '' ) eq 'input' ){
			$_ .= $Tab . $WireListName[ $Cnt ] . ",\n";
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

### set bus size #############################################################
# syntax:
#   $SetBusSize( <wire>, <wire|size> )

sub SetBusSize {
	local( $_ ) = @_;
	my( $i );
	
	/($CSymbol)\s*,\s*([\w\d_]+)/;
	my( $Name, $Bus ) = ( $1, $2 );
	
	if( $Bus =~ /$CSymbol/ ){
		if(( $i = SearchWire( $Bus )) < 0 ){
			print( "SetBusWire: unknown signal: $Bus\n" );
			$Bus = 1;
		}else{
			$Bus = $WireListWidth[ $i ];
		}
	}
	
	if(( $i = SearchWire( $Name )) < 0 ){
		print( "SetBusWire: unknown signal: $Name\n" );
	}else{
		$WireListWidth[ $i ] = $Bus;
		$WireListAttr [ $i ] &= ~$ATTR_WEAK_W;
	}
}

### cpp directive # 0 "hogehoge" #############################################

sub CppDirectiveLine{
	
	my( $Line ) = @_;
	
	if( $Line =~ /^#\s*(\d+)\s+"(.*)"/ ){
		$. = $1 - 1;
		$DefFile = ( $2 eq "-" ) ? $ARGV[ 0 ] : $2;
	}else{
		PrintRTL( $Line );
	}
}

### CPP directive ���� #######################################################

sub AddCppMacro {
	my( $Name, $Macro, $Args ) = @_;
	
	$Macro	= '1' if( !defined( $Macro ));
	$Args	= 's' if( !defined( $Args ));
	
	if(
		defined( $DefineTbl{ $Name } ) &&
		( $DefineTbl{ $Name }->[ 0 ] != $Args || $DefineTbl{ $Name }->[ 1 ] != $Macro )
	){
		Warning( "redefined macro '$Name'" );
	}
	
	$DefineTbl{ $Name } = [ $Args, $Macro ];
}

sub CppDirective {
}

### CPP �ޥ���Ÿ�� ###########################################################

sub ExpandMacro {
	local( $_ ) = @_;
	my $Line;
	my $Line2;
	my $Name;
	my $bReplaced = 1;
	my( $ArgList, @ArgList );
	my $ArgNum;
	my $i;
	
	while( $bReplaced ){
		$bReplaced = 0;
		$Line = '';
		
		while( /\b($CSymbol)\b(.*)/s ){
			$Line .= $`;
			( $Name, $_ ) = ( $1, $2 );
			
			if( !defined( $DefineTbl{ $Name } )){
				# �ޥ���ǤϤʤ�
				$Line .= $Name;
			}elsif( $DefineTbl{ $Name }->[ 0 ] eq 's' ){
				# ñ��ޥ���
				$Line .= $DefineTbl{ $Name }->[ 1 ];
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
							$ArgNum = $DefineTbl{ $Name }->[ 0 ];
							$ArgNum = -$ArgNum - 1 if( $ArgNum < 0 );
							
							if( !(
								$DefineTbl{ $Name }->[ 0 ] >= 0 ?
									( $ArgNum == $#ArgList + 1 ) : ( $ArgNum <= $#ArgList + 1 )
							)){
								Error( "invalid number of macro arg: $Name" );
								$Line .= $Name . '()';
							}else{
								# ��������°������ִ�
								$Line2 = $DefineTbl{ $Name }->[ 1 ];
								for( $i = 0; $i < $ArgNum; ++$i ){
									$Line2 =~ s/\b__\$ARG_${i}\$__\b/$ArgList[ $i ]/g;
								}
								
								# ���Ѱ������ִ�
								if( $DefineTbl{ $Name }->[ 0 ] < 0 ){
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
	$_;
}
