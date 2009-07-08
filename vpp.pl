#!/usr/bin/perl

##############################################################################
#
#		vpp -- verilog preprocessor		Ver.1.00
#		Copyright(C) by DDS
#
#	$Id$
#
##############################################################################
#
#	2004.07.12	input 宣言等のタブ不ぞろい等を整形するようにした
#	2004.07.13	parameter をインスタンス時に変えれるようにした #(...)
#	2004.07.26	$AllInputs 追加
#				$Eval マクロ実装
#	2004.07.14	(perlpp) #include MACRO に対応
#	2004.07.16	ポート名をソートするようにした
#	2004.07.30	ANSI 形式ポート宣言に対応
#	2004.08.02	`define --> #define 変換をやめた (こんなことしてたとは...)
#	2005.11.18	$repeat 追加
#				$perl 追加 (最強...)
#	2005.11.30	[HOGE-1:0] などの不明バス幅のとき，$ATTR_WEAK_W をつけてお茶を濁す
#				普通のポート宣言のファイルを通すとおかしなファイルを吐くのを修正
#				[perlpp] #ifdef <expr> の評価を強力にした
#				input hoge,hoge2; 等がバグってた
#	2005.12.02	変数名が end.* だとバグってた
#	2005.12.05	$perl 処理タイミングを $repeat と同じに変更
#	2005.12.06	$repeatplus 追加
#				eval() のコンパイルエラー表示
#				$repeat( A ) とかのエラー表示
#				$AutoFix ( Hi-Z を自動的に固定 ) 追加
#	2005.12.07	$repeat( 0 ) に対応
#	2005.12.20	$requre 追加・@INC に -I パス追加
#	2006.01.20	enum 使用時の perlpp に -nl 追加
#	2006.01.27	instance の attr に U 追加
#				[0:0] と '' を同一 bit 幅にみなすようにした
#	2006.04.15	attr の UNC を使用可能にした
#	2006.06.08	unmatch width 警告にモジュール名を表示
#	2006.08.21	enum の bit width 定数を hoge_W --> hoge_w に変更
#	2006.09.04	[X] でバス幅定義省略可能
#				typeof / sizeof 追加
#	2006.09.08	バス幅が 0? のとき X にするのをやめた
#	2006.09.14	instance で { hoge1, hoge2 } が wire 接続されている場合，
#				それぞれをバス幅不明で個々に登録する
#	2006.10.13	休出直前バージョン - instance で {6{1'b1}} を使用可にした
#	2007.12.06	C-like ポート宣言内 parameter を削除
#	2007.12.17	repeat に star, step パラメータ追加
#				repeatplus 排除
#	2007.12.27	enum 定数を #define → parameter に変更
#	2008.03.25	reg\t → reg に修正した箇所がある
#	2008.04.22	# 2 "hoge" などのファイル名変更以外の #hoge をスルー出力
#	2008.04.23	$repeat の マイナスステップに対応
#
##############################################################################
$enum = 1;

$ATTR_REF		= $enum;				# wire が参照された
$ATTR_FIX		= ( $enum <<= 1 );		# wire に出力された
$ATTR_BYDIR		= ( $enum <<= 1 );		# inout で接続された
$ATTR_IN		= ( $enum <<= 1 );		# 強制 I
$ATTR_OUT		= ( $enum <<= 1 );		# 強制 O
$ATTR_INOUT		= ( $enum <<= 1 );		# 強制 IO
$ATTR_WIRE		= ( $enum <<= 1 );		# 強制 W
$ATTR_REG		= ( $enum <<= 1 );		# outreg / ioreg ( Add repo 抑制 )
$ATTR_MD		= ( $enum <<= 1 );		# multiple drv ( 警告抑制 )
$ATTR_NP		= ( $enum <<= 1 );		# print 不要 ( .def でポート宣言済み )
$ATTR_DC_WEAK_W	= ( $enum <<= 1 );		# Bus Size は弱めの申告警告を抑制
$ATTR_WEAK_W	= ( $enum <<= 1 );		# Bus Size は弱めの申告
$ATTR_NC		= 0xFFFFFFFF;

$CSymbol		= '\b[_a-zA-Z]\w*\b';
#$DefSkelPort	= "[io]?(.*)";
$DefSkelPort	= "(.*)";
$DefSkelWire	= "\$1";
$UnknownBusType	= '\[X[^\]]*\]';

$tab0 = 8;
$tab1 = 28;
$tab2 = 52;

$ErrorCnt = 0;

$OpenClose = qr/\([^()]*(?:(??{$OpenClose})[^()]*)*\)/;
$Debug	= 0;

$MODMODE_NORMAL		= 0;
$MODMODE_TEST		= 1;
$MODMODE_TESTINC	= 2;

$bPrintRTL_Enable	= 1;

&main();
exit( $ErrorCnt != 0 );

### main procedure ###########################################################

sub main{
	local(
		$Line,
		$Line2,
		$Word,
	);
	
	if( $#ARGV < 0 ){
		print( "usage: vpp.pl <Def file>\n" );
		return;
	}
	
	$LineCnt = 0;
	
	# vpp.pl 実行 dir の設定 perlpp 用
	
	$VppDir = $0;
	$VppDir =~ s|\\|/|g;
	
	$VppDir = ( $VppDir =~ /(.*\/)/ ) ? $1 : "";
	
	# -DMACRO setup
	$CppMacroDef = '';
	
	while( $ARGV[ 0 ] =~ /^-[IDv]/ ){
		$CppMacroDef .= ' ' . $ARGV[ 0 ];
		
		$Debug = 1 if( $ARGV[ 0 ] =~ /^-v/ );
		
		push( @INC, $1 ) if( $ARGV[ 0 ] =~ /^-I(.*)/ );
		shift( @ARGV );
	}
	
	# set up default file name
	
	$DefFile  = $ARGV[ 0 ];
	
	$DefFile =~ /(.*?)(\.def)?(\.[^\.]+)$/;
	
	$RTLFile  = "$1$3";
	$RTLFile  = "$1_top$3" if( $RTLFile eq $DefFile );
	$ListFile = "$1.list";
	$CppFile  = "$1.cpp$3";
	$VppFile  = "$1.vpp$3";
	
	unlink( $ListFile );
	
	&VPreProcessor( $DefFile, $CppFile, "-l" . $CppMacroDef );
	
	system( "cp $CppFile stage1" ) if( $Debug );
	
	# expand $repeat
	if( !open( fpDef, "< $CppFile" )){
		&Error( "can't open file \"$CppFile\"" );
		return;
	}
	
	open( fpRTL, "> $VppFile" );
	
	$LineCnt = 0;
	&ExpandRepeatParser( 0 );
	
	close( fpRTL );
	close( fpDef );
	
	system( "cp $VppFile stage2" ) if( $Debug );
	
	rename( $VppFile, $CppFile );
	
	# vpp
	if( !open( fpDef, "< $CppFile" )){
		&Error( "can't open file \"$CppFile\"" );
		return;
	}
	
	open( fpRTL, "> $VppFile" );
	
	$LineCnt = 0;
	$bParsing = 1;
	&MultiLineParser( $Line );
	
	close( fpRTL );
	close( fpDef );
	
	unlink( $CppFile );
	
	if( $bPostProcess ){
		system( "cp $VppFile stage3" ) if( $Debug );
		
		# 遅延バスサイズ定義用 バスサイズ出力
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
		
		&VPreProcessor( $CppFile, $RTLFile, '-nl' . $CppMacroDef );
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
	
	local( $fp ) = @_;
	local(
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

### マルチラインパーザ #######################################################

sub MultiLineParser {
	
	while( $Line = <fpDef> ){
		++$LineCnt;
		
		( $Word, $Line2 ) = &GetWord( $Line );
		
		if    ( $Line =~ /^#/			){ &CppDirective( $Line );
		}elsif( $Word eq 'module'		){ &StartModule( $Line2 );
		}elsif( $Word eq 'endmodule'	){ &EndModule( $Line );
		}elsif( $Word eq 'instance'		){ &DefineInst( $Line2 );
		}elsif( $Word eq 'enum'			){ &Enumerate( $Line2 );
		}elsif( $Word eq '$file'		){ &DefineFileName( $Line2 );
		}elsif( $Word eq '$wire'		){ &DefineDefWireSkel( $Line2 );
		}elsif( $Word eq '$header'		){ &OutputHeader();
		}elsif( $Word eq '$repeat'		){ &RepeatOutput( $Line2 );
		}elsif( $Word eq '$end'			){ return;
		}elsif( $Word eq 'testmodule'	){ &StartModule( $Line2 ); $iModuleMode = $MODMODE_TEST;
		}elsif( $Word eq 'testmodule_inc'){ &StartModule( $Line2 ); $iModuleMode = $MODMODE_TESTINC;
		}elsif( $Word eq '$AllInputs'	){ &PrintAllInputs( $Line2, $Line );
		}elsif( $Word eq '$AutoFix'		){ $bAutoFix = ( $Line2 =~ /\bon\b/ );
		}elsif( $Word eq '$SetBusSize'	){ &SetBusSize( $Line );
		}else							 { &PrintRTL( $Line );
		}
	}
}

### Start of the module #####################################################

sub ExpandRepeatParser {
	my( $bRepeating ) = @_;
	local( $_ );
	
	while( <fpDef> ){
		++$LineCnt;
		
		( $Word, $Line2 ) = &GetWord( $_ );
		
		if    ( $Word eq '$repeat'		){ &RepeatOutput( $Line2 );
		}elsif( $Word eq '$end'			){ return;
		}elsif( $Word eq '$perl'		){ &ExecPerl( $Line2 );
		}elsif( $Word eq '$require'		){ &Require( $Line2 );
		}else							 {
			$_ = &ExpandPrintfFmt( $_, $RepCnt ) if( $bRepeating );
			
			&PrintRTL( $_ );
		}
	}
}

sub ExpandPrintfFmtSub {
	local( $_, $Num ) = @_;
	return( sprintf( $_, $Num ));
}

sub ExpandPrintfFmt {
	local( $_, $Num ) = @_;
	s/(%[+\-\d\.#]*[%cCdiouxXeEfgGnpsS])/&ExpandPrintfFmtSub($1,$Num)/ge;
	return( $_ );
}

### Start of the module #####################################################

sub StartModule{
	local( $Line ) = @_;
	local(
		@ModuleIO,
		@IOList,
		$InOut,
		$BitWidth,
		$Attr
	);
	
	# wire list 初期化
	
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
	
	#&PrintRTL( &SkipToSemiColon( $Line ));
	#&SkipToSemiColon( $Line );
	
	# ); まで読む 何か読めたらそれをポートリストとみなす
	
	if( $Line !~ /^\s*;/ ){
		
		my( $CLikePortDef ) = 0;
		
		while( <fpDef> ){
			++$LineCnt;
			last if( /\s*\);/ );
			next if( /^\s*\(\s*$/ || /^#/ );
			
			$CLikePortDef |= /^\s*(?:wire|reg|input|output|outreg|inout|ioreg)\b/;
			
			/^\s*(wire|reg\t?|input|output|outreg|inout|ioreg)\s*(\[[^\]]+\])?\s*(.*)/;
			if( $1 ){
				#if( $2 eq '' ){
				if( !defined( $2 )){
					$_ = "$1\t\t\t$3\n";
				}else{
					$_ = "$1\t$2\t$3\n";
				}
			}
			$PortDef .= $_;
			
			next if( /^\s*(?:reg|wire|parameter)\b/ );
			
			s/^(?:input|output|outreg|inout|ioreg)\s+(?:\[[^\]]+\])?\s+//g;
			s/^/\t/;
			s/;/,/;
			$PortList .= $_;
		}
		
		$PortDef	= '' if( !$CLikePortDef );
		$PortList	= '' if( !$CLikePortDef );
	}
	
	# 親 module の wire / port リストをget
	
	@ModuleIO = &GetModuleIO( $ModuleName, $CppFile );
	
	# input/output 文 1 行ごとの処理
	
	while( $Line = shift( @ModuleIO )){
		
		@IOList = split( / /, $Line );
		$InOut = shift( @IOList );
		
		$BitWidth = "";
		
		while( $Port = shift( @IOList )){
			
			# bit width が指定された
			
			if( $Port =~ /^\d/ ){
				$BitWidth = $Port;
				next;
			}
			
			$Attr = ( $InOut eq "input" )	? ( $ATTR_NP | $ATTR_IN )	:
					( $InOut eq "output" )	? ( $ATTR_NP | $ATTR_OUT )	:
					( $InOut eq "inout" )	? ( $ATTR_NP | $ATTR_INOUT ):
					( $InOut eq "wire" )	? ( $ATTR_NP | $ATTR_WIRE )	:
					( $InOut eq "reg" )		? ( $ATTR_NP | $ATTR_WIRE | $ATTR_REF )	:
					( $InOut eq "outreg" )	? ( $ATTR_OUT  | $ATTR_REG ):
					( $InOut eq "ioreg" )	? ( $ATTR_INOUT| $ATTR_REG ):
					( $InOut eq "assign" )	? ( $ATTR_FIX | $ATTR_WEAK_W ):
											  0;
			
			if( $BitWidth eq '0?' ){
				$Attr |= $ATTR_WEAK_W;
				#$BitWidth = "X";
			}
			
			$BitWidth = "X" if( $InOut eq "assign" );
			&RegisterWire( $Port, $BitWidth, $Attr, $ModuleName );
		}
	}
}

### End of the module ########################################################

sub EndModule{
	local( $Line ) = @_;
	local(
		$Type,
		$bFirst,
		$i
	);
	
	my( $MSB, $LSB, $MSB_Drv, $LSB_Drv );
	
	# expand bus
	
	&ExpandBus();
	
	&PrintRTL( "//" ) if( $iModuleMode == $MODMODE_TESTINC );
	&PrintRTL( $Line );
	$bInModule = 0;
	
	# module port リストを出力
	
	#&SortPort();
	
	$bFirst = 1;
	&PrintRTL( "//" ) if( $iModuleMode == $MODMODE_TESTINC );
	&PrintRTL( "module $ModuleName" );
	
	if( $iModuleMode == $MODMODE_NORMAL ){
		
		$bCLikePortDef = $PortList ne "";
		
		for( $i = 0; $i < $WireListCnt; ++$i ){
			
			$Type = &QueryWireType( $i, $bCLikePortDef ? 'd' : '' );
			
			if( $Type eq "input" || $Type eq "output" || $Type eq "inout" ){
				#&PrintRTL( "\t$WireListName[ $i ],\n" );
				$PortList .= "\t$WireListName[ $i ],\n";
			}
		}
		
		if( $PortList ){
			$PortList =~ s/,([^,]*)$/$1/;
			&PrintRTL( "(\n$PortList)" );
		}
		
	}
	
	&PrintRTL( ";\n$PortDef" );
	
	# in/out/reg/wire 宣言出力
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		if(( $Type = &QueryWireType( $i, "d" )) ne "" ){
			
			if( $iModuleMode != $MODMODE_NORMAL ){
				$Type = "reg"  if( $Type eq "input" );
				$Type = "wire" if( $Type eq "output" || $Type eq "inout" );
			}
			
			&PrintRTL((( $Type eq "reg" ) ? "reg\t" : $Type ) . "\t" );
			
			if( $WireListWidth[ $i ] eq "" ){
				# bit 指定なし
				&PrintRTL( "\t" );
			}elsif( $WireListWidth[ $i ] =~ /(\d+):(\d+)/ ){
				# 10:2 とか
				&PrintRTL( "[$WireListWidth[ $i ]]" );
			}else{
				# 10:0 とか
				&PrintRTL( "[$WireListWidth[ $i ]:0]" );
			}
			
			&PrintRTL( "\t$WireListName[ $i ];\n" );
		}
	}
	
	# Hi-Z autofix
	
	if( $bAutoFix ){
		for( $i = 0; $i < $WireListCnt; ++$i ){
			
			( $MSB,	$LSB ) = &GetBusWidth( $WireListWidth[ $i ] );
			
			if( defined( $WireListWidthDrv[ $i ] )){
				( $MSB_Drv, $LSB_Drv ) = GetBusWidth( $WireListWidthDrv[ $i ] );
				
				# 部分代入されている
				if( $MSB > $MSB_Drv ){
					&PrintRTL( sprintf( "\tassign %s[%d:%d]\t= %d'd0;\n",
						$WireListName[$i], $MSB, $MSB_Drv + 1, $MSB - $MSB_Drv
					));
				}elsif( $LSB < $LSB_Drv ){
					&PrintRTL( sprintf( "\tassign %s[%d:%d]\t= %d'd0;\n",
						$WireListName[$i], $LSB_Drv - 1, $LSB_Drv, $LSB_Drv - $LSB
					));
				}
			}else{
				# 代入されていない
				&PrintRTL( sprintf( "\tassign $WireListName[$i]\t= %d'd0;\n", $MSB - $LSB + 1 ));
			}
		}
	}
	
	# buf にためてきた記述をフラッシュ
	
	print( fpRTL $RTLBuf );
	$RTLBuf = "";
	
	# wire リストを出力 for debug
	&OutputWireList();
}

### Evaluate #################################################################

sub EvaluateLine {
	local( $_ ) = @_;
	s/\$Eval($OpenClose)/&Evaluate($1)/ge;
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
	local( $tmp );
	return if( !$bPrintRTL_Enable );
	
	s/\$Eval($OpenClose)/&Evaluate($1)/ge;
	
	# (in|out)put  [X] hoge〜 処理
	if( $bParsing ){
		if( /$UnknownBusType/ ){
			s/$UnknownBusType(\s+)($CSymbol)/TYPEOF_$2$1$2/g;
			
			$bPostProcess = 1;
		}
		
		s/\bsizeof\s*\(\s*($CSymbol)\s*\)/SIZEOF_$1/g;
		s/\btypeof\s*\(\s*($CSymbol)\s*\)/TYPEOF_$1/g;
	}
	
	# outreg / ioreg 処理
	
	if( /\b(out|io)reg\b/ ){
		$tmp = $_;
		
		s/\boutreg\b/output/g || s/\bioreg\b/inout/g;
		$tmp =~ s/\b(out|io)reg\b/reg\t/g;
		
		$_ .= $tmp;
	}
	
	# Case / FullCase 処理
	
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
#		a(\d+)	aa[$1]			// バス結束例
#		b		bb$n			// バス展開例
#	);
#
#	アトリビュート: <修飾子><ポートタイプ>
#	  修飾子:
#		M		Multiple drive 警告を抑制する
#		B		bit width weakly defined 警告を抑制する
#		U		tmpl isn't used 警告を抑制する
#	  ポートタイプ:
#		NP		reg/wire 宣言しない
#		NC		Wire 接続しない
#		W		ポートタイプを強制的に wire にする
#		I		ポートタイプを強制的に input にする
#		O		ポートタイプを強制的に output にする
#		IO		ポートタイプを強制的に inout にする

sub DefineInst{
	local( $Line ) = @_;
	
	local(
		@SkelListPort,
		@SkelListWire,
		@SkelListAttr,
		@SkelListUsed,
		$SkelListCnt,
		
		$Port,
		$Wire,
		$WireBus,
		$Attr,
		
		@ModuleIO,
		@IOList,
		$InOut,
		$BitWidth,
		
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
		&Error( "syntax error" );
		return;
	}
	
	# get module name, module inst name, module file
	
	local( $ModuleName, $ModuleParam, $ModuleInst, $ModuleFile ) = ( $1, $2, $3, $4 );
	
	if( $ModuleInst eq "*" ){
		$ModuleInst = $ModuleName;
	}
	
	if( $ModuleFile eq "*" ){
		$ModuleFile = $CppFile;
	}
	
	# read port->wire tmpl list
	
	&ReadSkelList() if( $5 eq "(" );
	
	# instance の header を出力
	
	&PrintRTL( "\t$ModuleName$ModuleParam $ModuleInst" );
	$bFirst = 1;
	
	# get sub module's port list
	
	@ModuleIO = &GetModuleIO( $ModuleName, $ModuleFile );
	
	# input/output 文 1 行ごとの処理
	
	while( $Line = shift( @ModuleIO )){
		
		@IOList = split( / /, $Line );
		$InOut = shift( @IOList );
		
		$InOut = "output" if( $InOut eq "outreg" );
		$InOut = "inout"  if( $InOut eq "ioreg" );
		
		next if( $InOut !~ /^(?:input|output|inout)$/ );
		$BitWidth = "";
		
		while( $Port = shift( @IOList )){
			
			# bit width が指定された
			
			if( $Port =~ /^\d/ ){
				$BitWidth = $Port;
				next;
			}
			
			( $Wire, $Attr ) = &ConvPort2Wire( $Port, $BitWidth );
			
			if( $Attr != $ATTR_NC ){
				
				# hoge(\d) --> hoge[$1] 対策
				
				$WireBus = $Wire;
				if( $WireBus  =~ /(.*)\[(\d+:?\d*)\]$/ ){
					
					$WireBus		= $1;
					$BitWidthWire	= $2;
					$BitWidthWire	= $BitWidthWire =~ /^\d+$/ ? "$BitWidthWire:$BitWidthWire" : $BitWidthWire;
					
					# instance の tmpl 定義で
					#  hoge  hoge[1] などのように wire 側に bit 指定が
					# ついたとき wire の実際のサイズがわからないため
					# ATTR_WEAK_W 属性をつける
					$Attr |= $ATTR_WEAK_W;
				}else{
					
					# BusSize が [BIT_DMEMADR-1:0] などのように不明の場合，0? に変換される．
					# そのときは $ATTR_WEAK_W 属性をつける
					
					if( $BitWidth eq '0?' ){
						$Attr |= $ATTR_WEAK_W;
						$BitWidthWire	= '';
					}else{
						$BitWidthWire	= $BitWidth;
					}
				}
				
				# wire list に登録
				
				if( $Wire !~ /^\d/ ){
					$Attr |= ( $InOut eq "input" )	? $ATTR_REF		:
							 ( $InOut eq "output" )	? $ATTR_FIX		:
													  $ATTR_BYDIR	;
					
					# wire 命を修正
					
					$WireBus =~ s/\d+'[hdob]\d+//g;
					$WireBus =~ s/[\s{}]//g;
					$WireBus =~ s/\b\d+\b//g;
					
					@_ = split( /,+/, $WireBus );
					
					if( $#_ > 0 ){
						# { ... , ... } 等，concat 信号が接続されている
						
						foreach $WireBus ( @_ ){
							&RegisterWire(
								$WireBus,
								'X',
								$Attr |= $ATTR_WEAK_W,
								$ModuleName
							);
						}
					}else{
						&RegisterWire(
							$WireBus,
							$BitWidthWire,
							$Attr,
							$ModuleName
						) if( $WireBus ne '' );
					}
				}elsif( $Wire =~ /^\d+$/ ){
					# 数字だけが指定された場合，bit幅表記をつける
					$Wire = sprintf( "%d'd$Wire", &GetBusWidth2( $BitWidth ));
				}
			}else{
				# NC 指定
				$Wire = '';
			}
			
			# .hoge( hoge ), の list を出力
			
			PrintRTL( $bFirst ? "(\n" : ",\n" );
			$bFirst = 0;
			
			$tmp  = "\t" x (( $tab0 + 3 ) / 4 );
			$Len  = $tab0;
			
			$Wire =~ s/\$n//g;		#z $n の削除
			$tmp .= ".$Port";
			$Len += length( $Port ) + 1;
			$tmp .= "\t" x (( $tab1 - $Len + 3 ) / 4 );
			$Len  = $tab1;
			
			$tmp .= "( $Wire";
			$Len += length( $Wire ) + 2;
			
			if( $bAutoFix && $BitWidthWire ne '' && $Wire =~ /^$CSymbol$/ ){
				$tmp2 = "[$BitWidthWire]";
				$Len += length( $tmp2 );
				$tmp .= $tmp2;
			}
			
			$tmp .= "\t" x (( $tab2 - $Len + 3 ) / 4 );
			$Len  = $tab2;
			
			$tmp .= ")";
			
			&PrintRTL( "$tmp" );
		}
	}
	
	# instance の footer を出力
	
	&PrintRTL( "\n\t)" ) if( !$bFirst );
	&PrintRTL( ";\n" );
	
	# SkelList 未使用警告
	
	&WarnUnusedSkelList();
}

### search module & get IO definition ########################################

sub GetModuleIO{
	
	local( $ModuleName, $ModuleFile ) = @_;
	local(
		$Line,
		$_,
		$bFound
	);
	
	$bFound = 0;
	
	if( !open( fpGetModuleIO, "< $ModuleFile" )){
		&Error( "can't open file \"$ModuleFile\"" );
		return( "" );
	}
	
	# module の先頭を探す
	
	while( $Line = <fpGetModuleIO> ){
		
		if( $bFound ){
			# module の途中
			
			last if( $Line =~ /\bendmodule\b/ );
			$_ .= $Line;
			
		}else{
			# module をまだ見つけていない
			
			$bFound = 1 if( $Line =~ /\b(?:test)?module(?:_inc)?\s+$ModuleName\b/ );
		}
	}
	
	close( fpGetModuleIO );
	
	if( !$bFound ){
		&Error( "can't find module \"$ModuleName@$ModuleFile\"" );
		return( "" );
	}
	
	# delete comment
	
	s|//\*|// \*|g;
	s/\/\*.*?\*\///gs;
	s/\btask\b.*?\bendtask\b//gs;
	s/\bfunction\b.*?\bendfunction\b//gs;
	s/\x23.*//g;
	s/\/\/.*//g;
	s/`.*//g;
	
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
	
	# port 以外を削除
	
	s/(.*)/&DeleteExceptPort($1)/ge;
	s/\s*\n+/\n/g;
	s/^\n//g;
	s/\n$//g;
	
	return( split( /\n/, $_ ));
}

sub DeleteExceptPort{
	local( $_ ) = @_;
	
	if( /^(?:input|output|inout|wire|reg|outreg|ioreg)\b/ ){
		
		#s/\[0:0\]/ /g;
		#s/\[(\d+):0\]/ $1 /g;
		
		# [10:2] とかの対策・・・ MSB:LSB を返す
		s/\[\s*(\d+)\s*:\s*(\d+)\s*\]/ $1:$2 /g;
		
		# ↑以外のバス表記のときは，不明バス幅にする (^^;
		s/\[[^\]]+\]/0?/;
		
		# typeof()は，不明バス幅にする (^^;
		s/typeof\s*\([^\)]+\)/0?/;
		
		s/[ ;,]+/ /g;
		
		# enum されたものを ビット数に変換
		s/^($CSymbol)\s+($CSymbol)/&ConvertEnum2Width( $1, $2 )/ge;
		
		# wire hoge = hoge の = 以降を削除
		s/=[^;,]*//g;
		
	}elsif( /^assign\b/ ){
		# assign のワイヤーは，= 直前の識別子を採用
		s/\s*=.*//g;
		/\s($CSymbol)$/;
		$_ = "assign $1";
	}else{
		$_ = '';
	}
	
	return( $_ );
}

### optimize line ( remove blank, etc... ) ###################################

sub OptimizeLine{
	local( $Line ) = @_;
	
	$Line =~ s/[\t ]+/ /g;
	$Line =~ s/\/\/.*//g;
	$Line =~ s/^ +//g;
	$Line =~ s/ +$//g;
	
	$Line =~ /^([\w\d\$]+)/;
	return( $Line, $1 );
}
### get word #################################################################

sub GetWord{
	local( $Line ) = @_;
	
	$Line =~ s/\/\/.*//g;	# remove comment
	
	if( $Line !~ /^\s*([\w\d\$]+)(.*)/ ){
		$Line =~ /^\s*(.)(.*)/;
	}
	
	return( $1, $2 );
}

### print error msg ##########################################################

sub Error{
	local( $Msg ) = @_;
	
	print( "$DefFile($LineCnt): $Msg\n" );
	++$ErrorCnt;
}

sub Warning{
	local( $Msg ) = @_;
	
	print( "$DefFile($LineCnt): Warning: $Msg\n" );
}

### define output file name ##################################################

sub DefineFileName{
	
	( $RTLFile ) = @_;
	$RTLFile =~ s/\s*(\S*)/$1/g;
}

### define default port --> wire name ########################################

sub DefineDefWireSkel{
	local( $Line ) = @_;
	
	if( $Line =~ /\s*(\S+)\s+(\S+)/ ){
		$DefSkelPort = $1;
		$DefSkelWire = $2;
	}else{
		&Error( "syntax error" );
	}
}

### output header ############################################################

sub OutputHeader{
	
	local( $sec, $min, $hour, $mday, $mon, $year ) = localtime( time );
	local( $DateStr ) =
		sprintf( "%d/%02d/%02d %02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );
	
	print( fpRTL <<EOF );
/*****************************************************************************

	$RTLFile -- $BaseName module	generated by vpp.pl
	
	Date     : $DateStr
	Def file : $DefFile

*****************************************************************************/
EOF
}

### skip to semi colon #######################################################

sub SkipToSemiColon{
	
	local( $Line ) = @_;
	
	do{
		goto ExitLoop if( $Line =~ s/.*?;//g );
		++$LineCnt;
	}while( $Line = <fpDef> );
	
  ExitLoop:
	return( $Line );
}

### read port/wire tmpl list #################################################

sub ReadSkelList{
	
	local(
		$Line,
		$Port,
		$Wire,
		$Attr
	);
	
	while( $Line = <fpDef> ){
		++$LineCnt;
		
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

### tmpl list 未使用警告 #####################################################

sub WarnUnusedSkelList{
	
	local( $i );
	
	for( $i = 0; $i < $SkelListCnt; ++$i ){
		if( $SkelListUsed[ $i ] != 1 ){
			&Warning( "tmpl isn't used ( $SkelListPort[ $i ] --> $SkelListWire[ $i ] \@ $ModuleInst )" );
		}
	}
}

### convert port name to wire name ###########################################

sub ConvPort2Wire{
	
	local( $Port, $BitWidth ) = @_;
	local(
		$SkelPort,
		$SkelWire,
		
		$Wire,
		$Attr,
		
		$i
	);
	
	for( $i = 0; $i < $SkelListCnt; ++$i ){
		# bit幅が 0 なのに SkelWire に $n があったら，
		# 強制的に hit させない
		next if( $BitWidth == 0 && $SkelListWire[ $i ] =~ /\$n/ );
		
		# Hit した
		last if( $Port =~ /^$SkelListPort[ $i ]$/ );
	}
	
	# find/and create wire name
	
	if( $i < $SkelListCnt ){
		
		# port tmpl 使用された
		$SkelListUsed[ $i ] = 1;
		
		$SkelPort = $SkelListPort[ $i ];
		$SkelWire = $SkelListWire[ $i ];
		$Attr	  = $SkelListAttr[ $i ];
		
		# NC ならリストを作らない
		
		if( $Attr == $ATTR_NC ){
			return( "", $Attr );
		}
		
	}else{
		
		$SkelPort = $DefSkelPort;
		$SkelWire = $DefSkelWire;
		$Attr	  = 0;
	}
	
	# $<n> の置換
	if( $SkelWire eq "" ){
		$SkelPort = $DefSkelPort;
		$SkelWire = $DefSkelWire;
	}
	
	$Wire =  $SkelWire;
	$Port =~ /^$SkelPort$/;
	
	$tmp1 = $1;
	$tmp2 = $2;
	$tmp3 = $3;
	$tmp4 = $4;
	
	$Wire =~ s/\$1/$tmp1/g;
	$Wire =~ s/\$2/$tmp2/g;
	$Wire =~ s/\$3/$tmp3/g;
	$Wire =~ s/\$4/$tmp4/g;
	
	return( $Wire, $Attr );
}

### wire の search ###########################################################

sub SearchWire{
	
	local( $Wire ) = @_;
	local(
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

### wire の登録 ##############################################################

sub RegisterWire{
	
	local( $Wire, $BitWidth, $Attr, $ModuleName ) = @_;
	local(
		$i
	);
	
	local( $MSB0, $MSB1, $LSB0, $LSB1 );
	
	if(( $i = SearchWire( $Wire )) >= 0 ){
		# すでに登録済み
		
		# ATTR_WEAK_W が絡む場合の BitWidth を更新する
		if(
			( $Attr					& $ATTR_WEAK_W ) == 0 &&
			( $WireListAttr[ $i ]	& $ATTR_WEAK_W ) != 0
		){
			# List が Weak で，新しいのが Hard なので代入
			$WireListWidth[ $i ] = $BitWidth;
			
			# list の ATTR_WEAK_W 属性を消す
			$WireListAttr[ $i ] &= ~$ATTR_WEAK_W;
			
		}elsif(
			( $Attr					& $ATTR_WEAK_W ) != 0 &&
			( $WireListAttr[ $i ]	& $ATTR_WEAK_W ) != 0
		){
			# List，新しいの ともに Weak なので，大きいほうをとる
			
			( $MSB0, $LSB0 ) = GetBusWidth( $WireListWidth[ $i ] );
			( $MSB1, $LSB1 ) = GetBusWidth( $BitWidth );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$WireListWidth[ $i ] = $BitWidth = "$MSB0:$LSB0";
			
		}elsif(
			( $Attr					& $ATTR_WEAK_W ) == 0 &&
			( $WireListAttr[ $i ]	& $ATTR_WEAK_W ) == 0
		){
			# 両方 Hard なので，サイズが違っていれば size mismatch 警告
			
			if( &GetBusWidth2( $WireListWidth[ $i ] ) != &GetBusWidth2( $BitWidth )){
				&Warning( "unmatch port width ( $ModuleName.$Wire $BitWidth != $WireListWidth[ $i ] )" );
			}
		}
		
		# 両方 inout 型なら，登録するほうを REF に変更
		
		if( $WireListAttr[ $i ] & $Attr & $ATTR_INOUT ){
			$Attr |= $ATTR_REF;
		}
		
		# multiple driver 警告
		
		if(
			( $WireListAttr[ $i ] & $Attr & $ATTR_FIX ) &&
			!( $Attr & $ATTR_MD )
		){
			&Warning( "multiple driver ( wire : $Wire )" );
		}
		
		$WireListAttr[ $i ] |= ( $Attr & ~$ATTR_WEAK_W );
		
	}else{
		# 新規登録
		$i = $WireListCnt;
		
		$WireListName [ $WireListCnt ] = $Wire;
		$WireListWidth[ $WireListCnt ] = $BitWidth;
		$WireListAttr [ $WireListCnt ] = $Attr;
		
		++$WireListCnt;
	}
	
	# ドライブされている bit width を計算
	# input か，instance で呼び出した module で output されている
	if( $Attr & ( $ATTR_IN | $ATTR_INOUT | $ATTR_FIX )){
		
		if( defined( $WireListWidthDrv[ $i ] )){
			# すでに代入されているほうと，大きいほうを取る
			( $MSB0, $LSB0 ) = GetBusWidth( $BitWidth );
			( $MSB1, $LSB1 ) = GetBusWidth( $WireListWidthDrv[ $i ] );
			
			$MSB0 = $MSB1 if( $MSB0 < $MSB1 );
			$LSB0 = $LSB1 if( $LSB0 > $LSB1 );
			
			$WireListWidthDrv[ $i ] = $BitWidth = "$MSB0:$LSB0";
			
		}else{
			# 初ドライブなので，そのまま代入
			$WireListWidthDrv[ $i ] = $BitWidth;
		}
	}
}


### query wire type & returns "in/out/inout" #################################
# $Mode eq "d" で in/out/wire 宣言文モード

sub QueryWireType{
	
	local( $i, $Mode ) = @_;
	
	local( $Attr ) = $WireListAttr[ $i ];
	
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
	
	local(
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
		$Type = &QueryWireType( $i, "" );
		
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
		&Error( "Bus size is 'X' ( wire : $WireListName[ $i ] )" )
			if( $WireListWidth[ $i ] eq 'X' );
		
		# bus width is weakly defined error
		&Warning( "Bus size is not fixed ( wire : $WireListName[ $i ] )" )
			if(( $WireListAttr[ $i ] & ( $ATTR_WEAK_W | $ATTR_DC_WEAK_W )) == $ATTR_WEAK_W );
	}
	
	@WireListBuf = sort( @WireListBuf );
	
	printf( "Wire info : Unresolved:%3d / Added:%3d ( $ModuleName\@$DefFile )\n",
		$WireCntUnresolved, $WireCntAdded );
	
	if( !open( fpList, ">> $ListFile" )){
		&Error( "can't open file \"$ListFile\"" );
		return;
	}
	
	print( fpList "*** $ModuleName wire list ***\n" );
	print( fpList @WireListBuf );
	close( fpList );
}

### expand bus ###############################################################

sub ExpandBus{
	
	local( $i );
	local(
		$Wire,
		$Attr,
		$BitWidth,
		$WireCnt
	);
	
	$WireCnt = $WireListCnt;
	
	for( $i = 0; $i < $WireCnt; ++$i ){
		if( $WireListName[ $i ] =~ /\$n/ && $WireListWidth[ $i ] ne "" ){
			
			# 展開すべきバス
			
			$Wire		= $WireListName[ $i ];
			$Attr		= $WireListAttr[ $i ];
			$BitWidth	= $WireListWidth[ $i ];
			
			# FR wire なら F とみなす
			
			if(( $Attr & ( $ATTR_FIX | $ATTR_REF )) == ( $ATTR_FIX | $ATTR_REF )){
				$Attr &= ~$ATTR_REF
			}
			
			if( $Attr & ( $ATTR_REF | $ATTR_BYDIR )){
				&ExpandBus2( $Wire, $BitWidth, 'ref' );
			}
			
			if( $Attr & ( $ATTR_FIX | $ATTR_BYDIR )){
				&ExpandBus2( $Wire, $BitWidth, 'fix' );
			}
			
			# List 情報の修正
			
			$WireListAttr[ $i ] |= ( $ATTR_REF | $ATTR_FIX );
		}
		
		$WireListName[ $i ] =~ s/\$n//g;
	}
}

sub ExpandBus2{
	
	local( $Wire, $BitWidth, $Dir ) = @_;
	local(
		$WireNum,
		$WireBus,
		$uMSB, $uLSB
	);
	
	# print( "ExBus2>>$Wire, $BitWidth, $Dir\n" );
	$WireBus =  $Wire;
	$WireBus =~ s/\$n//g;
	
	# $BitWidth から MSB, LSB を割り出す
	if( $BitWidth =~ /(\d+):(\d+)/ ){
		$uMSB = $1;
		$uLSB = $2;
	}else{
		$uMSB = $BitWidth;
		$uLSB = 0;
	}
	
	# assign HOGE = {
	
	&PrintRTL( "\tassign " );
	&PrintRTL( "$WireBus = " ) if( $Dir eq 'ref' );
	&PrintRTL( "{\n" );
	
	# bus の各 bit を出力
	
	for( $BitWidth = $uMSB; $BitWidth >= $uLSB; --$BitWidth ){
		$WireNum = $Wire;
		$WireNum =~ s/\$n/$BitWidth/g;
		
		&PrintRTL( "\t\t$WireNum" );
		&PrintRTL( ",\n" ) if( $BitWidth );
		
		# child wire を登録
		
		&RegisterWire( $WireNum, "", $Attr, $ModuleName );
	}
	
	# } = hoge;
	
	&PrintRTL( "\n\t}" );
	&PrintRTL( " = $WireBus" ) if( $Dir eq 'fix' );
	&PrintRTL( ";\n\n" );
}

### sort bus #################################################################

sub SortPort {
	
	local( $i, @WireList, $_ );
	
	@WireList = ();
	
	# ワイヤー名と属性をひとつの配列にまとめる
	
	for( $i = 0; $i < $WireListCnt; ++$i ){
		push( @WireList,
			( &QueryWireType( $i, '' ) eq 'wire' ? "\xFF" : '' ) .
			"$WireListName[$i]\t$WireListAttr[$i]\t$WireListWidth[$i]"
		);
	}
	
	# ソート
	@WireList = sort( @WireList );
	
	# 各配列に書き戻す
	for( $i = 0; $i < $WireListCnt; ++$i ){
		$WireList[ $i ] =~ /\xFF?(.*)/;
		
		( $WireListName[ $i ], $WireListAttr[ $i ], $WireListWidth[ $i ] ) =
			split( /\t/, $1 );
	}
}

### 10:2 形式の表記のバス幅を get する #######################################

sub GetBusWidth {
	local( $BusWidth ) = @_;
	
	if( $BusWidth =~ /^(\d+):(\d+)$/ ){
		return( $1, $2 );
	}
	return( $BusWidth, 0 );
}

sub GetBusWidth2 {
	local( $MSB, $LSB ) = &GetBusWidth( @_ );
	return( $MSB + 1 - $LSB );
}

### かつての本家 vpp.pl ######################################################

sub VPreProcessor{
	
	local( $Sce, $Dst, $Opt )	= @_;
	local( $Tmp )				= "vpp.tmp";
	local(
		$Line,
		$Blank
	);
	
	if( !open( fpVppOut, "| perl ${VppDir}perlpp $Opt > $Tmp" )){
		&Error( "can't exec cpp" );
		return;
	}
	&Error( "can't open file \"$Sce\"" ) if( !open( fpVppIn, "< $Sce" ));
	
	print( fpVppOut "# 1 \"$Sce\"\n" ) if( $Opt !~ /-nl\b/ );
	
	while( $Line = <fpVppIn> ){
		# $Line =~ s/('[bodh])/'$1/g;
		
		if( 0 ){
			$Line =~ s/`(define\s+\w[\w\d]*)$/#$1/g;
			$Line =~ s/`(ifdef)\b/#$1/g;
			$Line =~ s/`(else)\b/#$1/g;
			$Line =~ s/`(endif)\b/#$1/g;
		}
		
		$tmp = $Line;
		print( fpVppOut $Line );
	}
	
	close( fpVppIn );
	close( fpVppOut );
	
	&Error( "can't open file \"$Dst\"" ) if( !open( fpVppOut, "> $Dst" ));
	&Error( "can't open file \"$Tmp\"" ) if( !open( fpVppIn,  "< $Tmp" ));
	
	while( <fpVppIn> ){
		s|^\s*//#.*||g;
		
		if( /^\s*$/ ){
			++$Blank;
		}elsif( m|^#| || m|//#| ){	# ???
			$Blank = 1;
		}else{
			$Blank = 0;
		}
		
		if( $Blank <= 1 ){
			# s/'('[bodh])/$1/g;
			s/\s*##\s*//g;
			print( fpVppOut )
		}
	}
	
	close( fpVppIn );
	close( fpVppOut );
	unlink( $Tmp );
}

### cpp directive # 0 "hogehoge" #############################################

sub CppDirective{
	
	local( $Line ) = @_;
	
	if( $Line =~ /^#\s*(\d+)\s+"(.*)"/ ){
		$LineCnt = $1 - 1;
		$DefFile = ( $2 eq "-" ) ? $ARGV[ 0 ] : $2;
	}else{
		&PrintRTL( $Line );
	}
}

### repeat output ############################################################
# syntax:
#   $repeat( REPEAT_NUM )
#      ....
#   $end

sub RepeatOutput{
	my( $RepCntEd ) = @_;
	my( $RewindPtr ) = tell( fpDef );
	my( $bPrintEnb ) = $bPrintRTL_Enable;
	
	my( $RepCntSt, $Step );
	
	$RepCntEd =~ /($OpenClose)/;
	( $RepCntSt, $RepCntEd, $Step ) = &Evaluate2( $RepCntEd );
	
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
		&Error( "\$repeat() parameter isn't a number: ($RepCntSt,$RepCntEd,$Step)" );
		$RepCntEd = 0;
	}
	
	# リピート数 <= 0 時の対策
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
		seek( fpDef, $RewindPtr, SEEK_SET );
		&ExpandRepeatParser( 1 );
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
		++$LineCnt;
		
		last if( /^\s*$EofStr$/ );
#		s/#.*//;
		$PerlCode .= $_;
	}
	
#	$PerlCode =~ s/\$Eval\s*\(/(/g;
	$PerlCode = &EvaluateLine( $PerlCode );
	
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
	&PrintRTL( $_ );
}

### enum state ###############################################################
# syntax:
#	enum [<type name>] { <n0> [, <n1> ...] } [<reg name> ];

sub Enumerate{
	
	local( $Line ) = @_;
	local( $Buf )  = $Line;
	local(
		$TypeName,
		@EnumList,
		$BitWidth,
		$i
	);
	
	# post preprocess 要求
	
	$bPostProcess = 1;
	
	# ; まで Buf に溜め込む
	
	if( $Line !~ /;/ ){
		while( $Line = <fpDef> ){
			++$LineCnt;
			
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
	
	# enum type list に登録
	$EnumListWidth{ $TypeName } = $i;
	
	# enum list の define 出力
	for( $i = 0; $i <= $#EnumList; ++$i ){
		PrintRTL( "\tparameter\t$EnumList[ $i ]\t= $BitWidth\'d$i;\n" );
	}
}

sub ConvertEnum2Width{
	
	local( $type, $name ) = @_;
	
	if( !defined( $EnumListWidth{ $name } )){
		return( "$type $name" );
	}else{
		return( "$type $EnumListWidth{ $name }" );
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
		if( $WireListName[ $Cnt ] =~ /^$Param$/ && &QueryWireType( $Cnt, '' ) eq 'input' ){
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
# 使用制限:
#  [3:2] 等 LSB が 0 でないものには適用不可
#  wire より instance のポート幅が大きいと×

### requre ###################################################################

sub Require {
	if( $_[0] =~ /"(.*)"/ ){
		require $1;
	}else{
		&Error( "Illegal requre file name" )
	}
}

### set bus size #############################################################
# syntax:
#   $SetBusSize( <wire>, <wire|size> )

sub SetBusSize {
	local( $_ ) = @_;
	local( $i );
	
	/($CSymbol)\s*,\s*([\w\d_]+)/;
	local( $Name, $Bus ) = ( $1, $2 );
	
	if( $Bus =~ /$CSymbol/ ){
		if(( $i = &SearchWire( $Bus )) < 0 ){
			print( "SetBusWire: unknown signal: $Bus\n" );
			$Bus = 1;
		}else{
			$Bus = $WireListWidth[ $i ];
		}
	}
	
	if(( $i = &SearchWire( $Name )) < 0 ){
		print( "SetBusWire: unknown signal: $Name\n" );
	}else{
		$WireListWidth[ $i ] = $Bus;
		$WireListAttr [ $i ] &= ~$ATTR_WEAK_W;
	}
}
