import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// --- Metro Route Coordinates ---

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;
  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

const _m1Encoded = r'qu{`HeygsBABCIKYISGCIEI?c@EKCGGCICm@UkDOmC]iEE]EY@AA@O{@Ia@KUGGKGOCOGQCkDL]?WCOMGIwAaCDKEJKMiMsT@GAFGMuO{WAE@EADoAwBiJ{O@CABEKcKaQGOAA@@aLmR?C?BUa@{O{WFQGPU_@Ye@QQ[YaDgCy@[kA[YM[IKGWW_@_@]g@a@o@QYSk@GYGYG_@C]Gg@Ec@Aq@?o@Dy@?e@@AA@AqAAu@Co@OwA_@eBgE_Mk@mBc@iAYw@Ss@Ko@Oy@KkAGaAC_AA{@LiK?_@@?';
const _m2Encoded = r'yl|`HwvbsB?Gw@NoA\yCt@yAd@a@NcAVeANqAJu@?{@As@Eu@GaAOcAWk@Se@Ww@g@k@a@]_@]a@{CyE[g@A@@AOWS_@c@aAQa@[_As@}B]cBUyASyAKsAKkBEoAAoABiAFwAJmARmAn@_Dx@_DjGkWCCBB`B{GP{AN}BFiAxB_]C?B?`@aHJw@Jw@T{@Ry@l@gB^aA\u@b@w@j@{@\[l@q@|AaBnAaAbE_CxEwBlFqBzC}@zBm@nBi@AC@BDCf@Qh@Wr@g@dB}A~BqBx@cAn@_Aj@}@h@{A`@}ANaAZaBJ_AF{@DeA@eA?y@Ai@Go@{@kHk@oDA@@A_DsRqBwKuA}GkAqFA@@AQs@sCsOuA}HmCaO}@mFQ}@YwBMqAGcAI{@E_AAg@Eu@HiH?OAA@@DeW?sM?sIAoU@mL?aL?qFA{BE}BGuBIyBUeDEmECeAIsAc@cHAA@@GmAMqCCcA@a@?}AD_C@qAAcACeAA[a@sGOgAEaAEoB@mBJ{BJwBHkC@w@Cu@QqAE}@MgA_@kCc@aDMoAK}@GaAQyC@AA@CWEeAGiASmDSsC_@qGWcF[sFa@sH{AyXQyEIuBKcDQgDGB';
const _m3Encoded = r'uchaH}mosBB?Ep@GrAO`EI|BGrC?d@C~ABnA@vADz@D|@Jx@DfAFn@F`@Nv@VpAVrARjAVlAz@xCxAjGC@BAJ`@Pr@Lb@Ph@d@fB\lAL`@NXPZLVTTZVZPVP\Pr@^n@V|LdEvDrAfD|@xHxBtPjEp@RAF@G|JvCdO`EdO`EbN`ElCz@CDBEtHhC`O|EtJ|CCBBCVJfLtD`OlErEbB|JlDBFCGzGtBpFfBjEvApDhAjA^~IpCRF?A?@dAb@~Ad@|@V|@ZrA^ZJZNt@d@|@h@x@d@hO`KvEhDJF?C?BzAfAf@Zt@ZvAh@~A\|D\bJb@dMR|@@AC@BpCAnD@|EJpAH~ADfBF`AAdIe@CAB@l@Ab@Eb@G`JcApBYrFqAxAm@|@o@nCiCXYAC@BPUfAyAx@mBj@}AdB}FbAaEhBiGCAB@Pq@fCeJb@qAp@iBjA{CnEcKxB{E`A{Bj@oAZcA|BqJPy@EEDDnAwGjC_LpD}OECDBr@aDtCeOr@qCfLmb@x@oCvA}EjAoEC?B?Py@tEmPp@}CrFkSjAmFhAoFDQB@CA`@kBXiAf@aB~Ju[b@uA|@}BnAyD~@_D~BqJVaAB?C?tNqj@Nm@B@CAh@qBr@yCzCyOb@qBvCmPB@CAN{@ZyA~AuJLy@PwALmADs@Bi@Du@A}@@m@?k@A_@Ao@Cw@Ek@CaAKu@GeBa@oFa@sFGaAEw@Aa@?a@?}@BkB@m@L}EBcBHuCDuAHuGBw@JmBF_AH_ALaARyA`@}B^mBl@}Cx@kExA_HDD';
const _m4Encoded = r'elu`HqwasB?GJsF\wNRoLDsDGaIIqCQ{CQ{BcAaIUaB?E@CABiKym@cAaFq@eCY}@k@qA{@gB{@sA_AoAsBsBsAgAgAm@uAa@kMmDIA?K?JoVeG?C?BSGaFqAy@WsAg@w@k@iBeBy@mA}@yA}I}PsD}HAA@@gCgFe@_AkAyAoAsA_A}@kFkDCIBHyFwCaAs@mAmAy@sAkDiIAC@BgCeG_AiCcB_G}BgJqFuQs@}CYaCSoCCWBAC@u@kKUkBa@qB]_Be@gAu@{Aw@gAu@q@iA_AcBiAq@_@CCBBqQgJm@Yy@q@eA_Ay@aAg@w@i@iA?G';
const _h5Encoded = r'us}`HisesB{A?_A@mA?o@?eA?{CAw@?yCCs@?_A?mAAg@?u@?_CI_ACmAC]AUCU?QAuAHG@[DUD]DYB[BO@M?O?O?MAGAS?OAMAg@Co@Ci@CMAK?K?I?M@M@I@I@K@GBsBb@kMxB??o@Jc@Jy@Le@@}@DI?E?U?W@W?W?YAY?[A[AYA[CYA[CYCYEYCYEYEYEYGWEWGWGWGWIWGo@SUIWIUIUGWIUIWIYIWGWIWGWIWGWGUGWIUGmAYSEQESEUEUGWGUECAYGYGYGWGYGYGWGYGWGWGYGqA_@UIUKUMUKUOUMWOYOWOYQYOYQiEwCUQWQUQk@c@UQUQSSUSUSUSUUUUWUUWWSkAkAUSUUCCOOUSSSUSSSSSSSSSQSSUQUQUSYSWUWUWUSUSUQWMUMWKWIWGWGYGYGYG]G[E[E[E]E]A[C]?]A]@Y?W?U@U@gDFY@U@W@W?Y@W@W?U@W@U?W@YBYB[BYB[B]B[D[B[B[BYB[@[@Y@Y@Y?Y?Y?Y?WAY?W?W?WAW?U?W?WAY?[?[AYA[C[CYE[EYGYIYGWKYIWIYKWIWKWIWIWIWGWEWEWCYAYAYAYAY?YAY?Y@W?Y@W?Y@WBW@WDUDWDWFWFUHWJWJULULWNSNQJUPQLSLQLSLQLUNOLSLGDMHUPWNWPWPWPWPWPWPWRYPWPYPYPYLYLYJmA^YBYDY@g@@s@?SAQAYEWCSEQEQESEUIUIQISKSKUMWMGEMIWOYOWMWMWMUKWKUIWIUGWIWGYIYIYIYIYIYGYIYIWGWIWGWIWGWGUIYGWIYIYGWIWIWGWGWIUGWGUGUIWGWGWIYIYGYIYIYIYIWGYIWIYGWIWGWIWGWGUIWGWIYGYIYIYIYIWGYIYGWIYEYGWEYC_AI[As@?W@S@S?YBSBUBSBK@E@SDUDQDSFUFWHWHYHYH[HYFYFYD[DYBYDWDYDYDWBYDWDWBWDcALs@BY?Y?YCYAYEYEWEWCYEWEWEWEWE[CYC[CYC[CYCYAYCYCYCYCYCYCWAWCUCSASASCQAUCUASCQAWCIAOAQAUCWAWCYC[CYCYCYCYCYCYCWAWAW?W?W@WBYBYD[FYFYHWJYLWLWNWNWPURUPWRUPWRWTWRWTWRWRWRWTWRURWRUPWRURUPURUPURUPUPSPUPSPUPSPSPSNSPSNSNSNSNSLSJi@TUHUFUFWBUDU@W@U?U?UCSCSEUEQGSIQISKQKOMQKQMQKSOUOUOWQYQWQIEOKWQYSWQWQYQWQYQWQWQWQYQWQWQWOUQWQWOUQUOWOUOUQUOSOUMUOSOUOSMSMSOUOUOWQWQUSUSUUSWSWQWQ[YYOYQYQWQWQUQSQSSQSOQOSOUMSQWOUQWQWQWQWQWQWQUQWOUQWQUOUOUQQKSOOKOKQKOMQMWQSMSOUOWQUOUQWQUOUQUQUQUQUQSQUOUQSOUMUOSOUMSOUMSOSMCAOKSMSMSMSOa@WUOWQWQYQWOYQWQWQWOWQUOWQUOWOUOUOWOSOUOUOUMSOUOUOUOWOWQYQWQYQWOWOWMWKWKWIWGWEYEWEYC[C[C[C]C[E[C[C[Ck@E[C[E[C]C[Ck@G{@G]CuAMYC[CYCYCYCYCYCYCYCYAYAYAW?Y?Y?W@YBW@YDWBYFWDWFc@JWHUHWJUJWJUJUJWJUJWJULUJUJUJUJUJUHUJSJUHIDg@R]L]LYHwAf@y@VA@y@VYJ{@Xq@Tc@POHSJIDIFIDGDC@CBCBC@CBEDKJMLYTIJgCjC]\y@z@QRIJKJSXUXORQVi@`AOTi@bAo@jAm@fAa@t@m@hAg@|@m@hAKNOZSZQZQZSZQXQZSZQZQZQZQXQZOXOXOXOVOXOVOXMVOVOVMVOVOVOTOVOTQVQVUVEFMNUVUTUTWTURc@ZWPWPYNWLYNYJYLYJYH[H[HYF[H[Hg@JYHYFYFYFYFYHWFYFYFWFYHWFYFWFYHWHWHWJWHWJWJWHWJWJWHUJWJUHWHUJUHUHUJMDGBUHUHUJWHWJYJYJYJYLWJWHWJWHUJUHWJWHWJWJYJWJYJWJYJWJYJYJYJYJWJYJa@PWHUHWJWJWHWJWJWJYJWJYJYJWJYJYJYJYJYJWJYLYJYJYJYJWJYJYJWLYLe@RWNWNYNWNYLYPYNWNWNWLWLa@TWNWLWNWNWNYNc@Ve@VWNWNULUPUPUPURUTUTSVUVmAhBOXQXMZOVMXMVMXMVMXOXMXMXMVMXMVKVMTS`@KTKTKRKRQ^O\OZOZKTKTKTGLCFKTKRKTIROXITMTMXOZOXQX[`@SRUPWPULe@NYHWH[Fg@HY@[?[CWEa@KUIUMUOSQSSSSQWMUMWKWK[KYI]I_@Gc@Ge@Cg@Ag@Ag@@i@Bi@Bg@Dk@Fg@Be@Dg@De@De@De@De@Fy@Bg@Bg@@e@@i@?g@?g@?e@Ag@Ae@Ag@Ce@Ce@G{@Ge@Gg@Ge@Mw@Ga@Ic@Mq@Ia@I_@Ga@Ic@Ia@Ow@Ic@Ke@Ie@Ke@Ig@Ou@Ic@Ic@Ic@Ic@Ic@Ic@Ow@Ic@Ic@Kc@Mu@Ic@Ic@Ic@Os@Ic@Ia@Ic@Ic@Ia@Ic@Ic@Ia@Gc@Ia@Mu@Gc@Gc@Gc@Ec@Iw@Ee@Ec@Ce@Ce@Ce@Ag@Ae@Ag@A}@?i@?g@?i@@i@@}@?i@@y@?e@@e@?e@@w@@e@?c@@e@?w@@c@?e@@w@@c@?e@@u@?c@@e@?c@@c@@u@?c@?a@@c@?a@@u@?g@@e@?i@?g@Ag@?i@C{@Ci@Ag@Ci@Ei@Eg@Ei@I}@Gi@Ky@Ie@Ga@Ia@G_@I_@I_@I]Om@K_@K]K]M]Sk@M]M[M]O[g@cAOYOYQWWc@QWQUYa@QUQUSUQUQS]a@KMEGQUSUQUSUQUQS[a@QSQU[_@QSQSOUQSY]QSY]QSOSQU[_@SUSWSWUYSWUWSWUW]e@UWSUSWSWUW]c@SUSWSW[a@SUSW[_@SUQU[_@QUOSY]OQOSOQOQMOSUCEo@w@OSg@m@IKMOIMIKIMc@q@_DwEm@}@Wa@qBwC}A_C';
const _h6Encoded = r'}tu`HyamsBbAw@JILKLIPKXOl@a@h@a@f@c@FC\YFERQRQTOTQRQTQTQTQTQRQROROPMNOPMPMPOPMPOPMPOPMROPOROPOROPORORORQRORORORQRORQTORQRQTORQTQROTQRQTQTQRQTQTQTQTQTQTQTQTSVQTQTSVQTSVSTQVSVSVSTQTQTQTQRQTORQTQRQTQRQTQTOTQTSTQTOTQTQVOTORMBATOVMVMTKRKTKRIRKRKRIRKRKRITKRKRKTIRKTKRKTIRKRKTKRKRITKRKTKRIRKTKRKRKTIRKRKTKRIRKTKRIRKTKRKTKRKTKTIRKTKTKRKTKTKRKTKTKRKTKTKTKTKTKTKTKTKTKTMTKRKTKTKTKTKTKTKTKTMTKTKTKTKTKTKTKTKTKTMTKTKTKTKVKTMVMVKVMTKTKTITKTITIVGTEVEXEVCXETCTCRAZEXCPCRCTCTCTCVCXCVCVCXAVAVCVAVAVAVAXAVAVCVAVAVAXAXAXCXAXAXAVATATATATATETGTITMTKRMTMTMTOTMnDqBTMTMTMROTORQRQRSTSRURURURURUPSPSPSNQPSPQPSNSPQPSPSPSPSPSRSPSPSPSRUPSRURUPSRURURURURURURURUTURURWTURWTUTWRWRURSZ_@RULOrBsDNQRUPOPORQTORMTOTMTMVKVKVKVIVIXIVKXIVKXIVITITKTGTITITIVIVITIVKXIVIXKXIVKVITITIVIVIVIVIXKXIVKVIXIVKTIVKTKTKTKRMTKTMTMTMTKVMTMFELGVOTOTOTOTOTQTOTQRQROTQRQRSRQPQRSRSTUTUTYTWVWTWTWTWTWRWTUTWRURUTURURSTSRQTOTQVMTOVMVOVMXOVOVMTMVMRMTKTMTMTMTMTKTMVMTMVKVKVIXKVIXGXGVGVCTETCVCVCTAVCXCVCVCVAXCVAVCVCXAVCVCVCVCVAVCTCVCXAVCXCXCXCZCXEXCXEVCVEVCVCXEVCXEXCXCVEZCXEXEZCXEVCXEB?PCVCTCVETCVCVCVEVCVEXCVCXEXCXEXCVEXCTCVETCTCTCTEVETEVEVEVEXEVEXGXEXEVEVGVEVEVETEVEVEVEXEVEVGXGVGXGXIXGVGVGTGRERGTERGRETGTETGRETGVGTGTGVETGVGVGXIVGXGVGXGTGVGTGTGTETGTGVGVGVGPEFATGTGREVGTGPEPEVGTETGVGVGXIZGZIh@M\IZIZGZIZIZI\GZIZIZIZGZIZI\I\I\ITEPCRAXAT?R?dALRFXJPFPHTHTJTJTHTJVJXLVJTJTJTHTJRJPJRJPJPJPJNJ@@LHVPTPVRTPNLPLNJNLPNRLPNRNRNRPTNRPTPVPTPVRTRVPVRVRVPVRTPVPTRTPTPTPTPTNRPTNRPTNRPRNTPRPTPTPTPRPTPRPRPRNRNPPRNPNRNRNRPTPRPTRTPVPTRTRVRVRVRTRVRTPRPRPTNRPRPTPTPRPTRTPTPVRTPRRTNPPRNRNRPTPRPTPRPTPTPTRTPTPRPRPRNRNRPRNRPRNRPTPTPTRTPDDLJRPPLPNNLPPTRNLLLPNPPRPRPRRRP`FtERRRRRPRRTRRRTRRRTRTRTTRRTPPPRPPPRPRPRPRNRPRPRPRPPPRPRPRPRPRRRPRPPRRPRRRPTRRPRRTRRRTRRRTRTTTRTRTTTTTRTRTTRPRRTRPPRRTPRRTTTRTRbExDTRRRTRRRTRTPTRTPVRVPTRTPTPTPTPTNRPTPTPVPVRVRVRVTVRVRTTTRVRTRTPTRHHHHTPRPRPTRTPTRTTTTRXRXPXP\N\N\N\L\NZPXNXPTRTRTRPRRTRRRTRTRTTTRRPRRRRTPRRRRTTRRTRTTRRTTTRTTRRTTTTRRRPNLRNPLNHLHNHJHTLTLTNVN@?JFRLVLPJ\RTL^T^RHFx@b@RLPJNNPNRRRTPZRZN\Tl@Rn@H^H`@Fb@Fb@Db@Bd@@d@?b@A`@Ab@C`@E`@E`@G`@I`@K`@M^M^O\QZQ\Q\Q\Q\OZQZOZOZOXOXMXMVMViA~BKRKVMVKTO\Qh@EFIXK\KXKZKZK^Kb@Id@Ih@E\Gl@En@C`@Ap@?`@?t@Br@Bb@Ft@Db@Jt@Nr@H`@Rr@Tn@NZRd@LRPXRXRVPRPPPRRPRRTTTTLLVVNNVVNNXXPNXZPPZXPRZXNPXXPNXXXZRPXZRPZZPR\Z\\RR\\RR\\TTZZRRZXNPXXPNXZPNZZPPZZPRZZRPZZRR\\PP\\RTZ^PRV^NRT\LRR\LTR^LVRb@LXRd@JZPh@JZPj@J^Pl@J^Pn@J`@Pp@Pp@L`@Pr@J^Pn@J^Nl@J\Nj@J\Nl@J^Pl@H^Pn@J`@Rn@J^Rp@Tp@L^Vp@L^Tl@NZVl@N\Xl@P\Xl@N\Xh@N\Vf@NZVh@P\Vh@P\Xj@N\Vh@PXVd@NVX`@PVZ`@RT\^TT`@\TRb@\XR`@XVP`@XRP`@VRN`@XTP`@X`@XTP`@XTN@@\VXPXTNJRLRNPJ\VRP^VRP`@VTP^XVN`@XTP`@ZVN`@ZVP`@XVP`@ZVP`@XTPb@ZVP`@\TR`@^PTZ\PTZ`@PV\`@PVZb@RXZd@PXZh@N\Vl@N^Tn@J`@Rr@H`@Nt@Hb@Nv@Fb@Jv@Fd@Jx@Dd@Hv@Bf@Fx@D|@Bz@@nABz@@|@@~@@f@@z@@d@@x@@d@@z@@f@Bz@?f@Bz@@f@@v@@d@@t@?b@@r@@b@@v@@d@@x@Bp@?f@@\@`@?X@\@^?f@@\@p@@b@@t@@d@@x@@f@@v@@d@@v@@b@@x@@d@@z@@f@@z@@f@@z@@d@@z@@f@Bz@?f@Bv@?d@D|B@t@@b@@v@@b@@x@@d@@x@@d@@z@@f@@z@@f@@x@@d@@v@@`@@r@@`@@r@@`@@r@@b@@t@?b@Bv@?d@Bv@?d@@d@@R?d@Bv@?d@Bv@?d@@d@@R?d@Bv@?d@Bv@?d@Bx@@f@@z@@f@@x@Bb@Bv@@`@Dt@Bb@Fv@Bd@Hv@Dd@Hv@Fd@Ht@F^Hp@F`@Hr@Fb@Jr@Fb@Jv@Fb@Jv@F`@Hr@F^Hp@F`@Jp@D`@Jp@D^Hn@F`@Hn@F`@Hr@F`@Jr@Fb@Jt@Fb@Fd@Jv@Fd@Jt@Fb@Hn@D^Jn@D^Hp@F^Jp@D`@Jr@F`@Hr@Fb@Jt@Fd@Jt@@HDXJv@F^Fd@D\DXF`@Fj@F^Hl@D^Jn@D`@Jp@D`@F`@Jr@Fb@Hr@Fb@Jt@Fb@Jt@Fb@Fd@Jr@D^Hl@D\F^Hl@F^D^Ll@H^Nn@H^L^Rl@N^N\N\Xh@PXZb@PTX`@PT\`@PT^d@PT\b@RTPT`@f@NPV\NPV\PRX\PTX^Z^PVRTZ`@RTZb@RT\b@RVRVRVRTZ`@NRZ^PTZ^PTZ`@RTZb@RT\b@PTPTPRNRNPNPLPNRNPVZNPV\NRX\NRX\PTX^RRX`@RTZ^Zb@RTPTZ`@PRNRNPNRPRNRPRX^PTPRPTPTZ^PTRVPTRTPVRTRV\b@RVRVRVHJHHPTPRNRPRNTPRPRNTPRPTPTPRRTPTPTPTRTPVRTPT\b@RTZb@RVRVTV\b@RVZ^NRNRNPNRPRNRNRPRX\PRNTPTPRRTPTPTRTPTRTRTPTTTRTRTRVTTRTTV^b@TVRVTVRTZ`@RTRTPVRTRVRTRVRV^`@RXTV^b@TXTVTXRVPTPPLPZ^VX\b@`@d@^d@b@f@Z`@\`@\`@\`@^`@`@^`@^b@^d@Zf@Zh@V^Pv@Zj@Pj@Rb@N`@Nb@Lb@Nb@Nb@Nd@Nd@Pl@Td@Nh@Ph@P`AZj@PdAXp@Pp@Rr@Rr@PlA\r@Pr@Rt@Rt@Rr@Rt@Rt@RpA^v@Rt@Rv@Tv@Rv@Tx@RrA^x@Tx@Tx@Rx@Tx@Tx@Tx@TtA^z@TtA^x@TvA^x@TvA`@x@TvA^x@Tx@Tz@Tx@Tx@Rz@Tx@Tx@Tz@Tx@Tz@TvA`@z@TtOfEz@Tz@Tz@Tz@Vz@Tz@Tz@Tz@Tz@Vz@TxA`@z@TxA`@z@TzA`@z@Tz@Vz@TxA`@|@Tz@Tz@Tz@VzA`@z@T|@Vz@T|@Tz@V|@TxA`@|@T|@Vz@Tz@Tx@Rx@Rt@Pt@PlAXn@Nl@Nj@Lf@Lt@Pj@Lf@Lf@Lh@Jh@Lh@Lh@Lj@Nj@Ll@Fl@Hl@Ll@Nl@Ll@Nn@Nn@Nd@JFBl@Lj@Nh@Jd@Ld@Jd@Jf@Rh@Tf@Vh@Vj@Pj@Tj@Tn@X`@Tb@Rb@Vb@Td@Tb@Vb@Td@Vb@Vd@Td@Vd@Vd@Vf@Vd@Xf@Vd@Vd@Vd@Tb@Vd@Vb@Tb@T`@T`@T`@Rp@^n@\n@\n@\n@\n@\p@^`@R`@T`@R`@T`@T`@T`@Tb@T`@Tb@Tb@Tb@Tb@Tb@Vb@Tb@Td@Vb@Vd@Td@Vb@Vd@Vd@Vd@Vf@Vf@Vl@Zn@^p@\n@^p@\p@^r@^p@^p@\r@^r@`@r@^r@^r@^r@`@r@^p@^l@\l@Zh@Xf@Xf@Vd@Vd@Vd@Vd@Tb@Vd@Tb@V`@Tb@T`@R`@T^Rp@^l@Zl@Zj@Zl@\l@Z|@f@~@f@p@\n@\p@\p@X`@Nb@Lb@Hb@Hd@Fb@Df@@d@?d@Af@Cf@Ef@Id@If@Kh@Mf@Kh@Kf@Mh@Kh@Mj@Kh@Mh@Mj@Oj@Mj@Oj@Oj@Oj@Ml@Ml@Oj@Ml@Mn@Ml@Ml@On@Mn@Ml@On@Mp@On@Mn@Op@Mr@Ov@Qx@Qx@Qx@Qz@Sz@Qz@Qz@Sz@Qz@Qz@Sz@Qv@Qv@Or@Qp@Mn@Ol@Mh@Kf@Kn@Kj@If@Gb@Kd@If@Mf@Kd@Kd@Kf@Kf@Mf@KZGLCh@Kh@Oj@Oj@Qj@Ql@Ml@Mp@Od@Kh@Kn@Or@Ut@Wr@]r@_@r@a@t@a@r@a@r@a@t@c@r@a@t@a@r@a@r@a@r@a@t@c@r@a@t@a@r@a@r@a@zDyBr@c@t@a@t@a@t@c@t@a@r@c@t@c@t@a@t@c@t@a@r@a@v@_@t@[v@Wv@SpC[rBCx@Dj@FL@v@Nx@Rv@Vt@Zt@`@r@b@r@f@r@d@p@h@r@f@r@f@r@f@r@f@p@f@r@f@r@f@r@f@r@h@r@f@r@f@r@h@t@h@t@f@t@h@t@h@r@h@r@h@r@d@n@b@n@\n@Xj@TxBp@b@Jn@Rl@Pn@Nj@Pj@Pj@Nj@Nh@Nh@Nh@Nj@Nj@Pj@Nj@Pj@Nh@Nh@Pf@Pd@Pd@Rb@Rd@Td@T?@d@Tf@Vd@Vf@Xh@Vf@Xh@XpE~Bz@b@f@X|J`F`A^l@Pl@Pn@Nn@Nl@LjGtAp@Np@Np@Np@Np@Np@Nn@Nl@Ll@Jh@Jf@Ft@Dn@@|@AbEWp@Er@Ep@Et@Gr@Et@Gb@Cb@Cb@Ed@Cb@Ed@Cd@CpBOd@Cf@Ed@Cf@Ef@Cf@Eh@Ef@Cf@Ej@El@Ep@Ep@Ep@Gp@Ep@Er@Gp@Er@Er@Gp@En@El@Ej@Eh@Cf@Eb@Cj@El@C`@CF?r@G`@Cl@G^C~AM';
const _h7Encoded = r'qax`HsaksBHGJIPIRM`@Sz@]xB}@v@]~CoANGNEPIXKb@OXIXIxBm@n@Q@?RG\GZIZGXE\GZEZG\GZE\G\Gl@I\E\Gj@G\EF?h@G\Ch@ERAVCRATAPAP?PA`@AVAV?RA^?LA\?P?h@@WAbEB`@A\A\C\E\Gj@O\KZMZOZQZSXSXWXWXWXYXWVWVWXWXUXSZSZQZOZM\IZK\G\E\E^A\A^@\@^D^D\FzHdBj@Lj@L^H\F\H\H^H\H^H\H^H\Hn@L\H^F^D\D^B\@\?\?XAB?\?^A\A\A\?\A\A^A\A^A^A\A\?\A\A\A^A\?^A\A^A^A\?\A\A\A\?\A\A^A\A^?\A^A^A\?ZA\A\A^A\?\A^A\A^?\A\A\A\?\A\A^A\A\?\A\A\A^A\?^A\A^A`@?^A^?`@?b@?`@?`@?`@?`@?^?`@?^A^?\A^?\A\Aj@A\A\?FAb@A\?\A\A\A^A\A^A^?\A^A^A`@A^?^A^?^B\D^F\J^LZN\PZTXTZXVZTZT\T^R`@Pb@Pd@Pd@Pd@Pb@P`@T^R\V\VZXXXVXRZRZNZLZH\H\D\Dl@@^?ZC\AZA\C\AZC\A^C\A\C^A\A\A\?\@\?Z@\@^B\@\@\@\B\@\@\@\@\B\@\@\@\BZ@d@@`@BZ@Z@Z@P@??H?\@d@BX@Z@\@ZBX@f@@d@Bd@@d@Bd@@f@Bd@@f@Bf@Bf@@f@Bf@BZ@X@Z@Z@Z@d@Bb@@`@B^@\@Z@`@Bd@@Z@h@B\@\@\B\@Z@Z@h@Bd@@b@@^@ZBZ@^@^@^@\@\@\D\Jn@`@h@`@HD';
const _h8Encoded = r'ca}`Hw`ysBKgBEo@AM?OAK?MAM?OAQ?Q?OAS?SASAQAUCi@IyA?AIwAMuBA[Ca@Ca@Es@Eq@Aa@Eu@Ca@Es@Eo@A]C_@C_@C_@C_@Cq@C_@Eq@Eq@Aa@Ca@Eq@Ca@Ca@Eq@Aa@Ca@Ca@Es@Cc@Ca@Cc@Eu@Ca@Eu@Ca@Aa@Eq@C]C]A]C_@Ck@C_@Em@?GAUEo@C]A_@Em@Eo@C_@C_@Eo@C_@E_@C_@Ca@Gq@Ca@Es@Ec@Ca@Cc@Cc@Aa@SeHCc@Ac@Ac@Ac@Ac@Ac@Cc@Ac@Au@Cc@Aa@As@Aa@Cs@Cs@Aa@Cc@Cq@Cc@Ca@Ca@Ec@Gs@Ca@Gu@Ea@Ec@Cc@Gs@Ec@Ec@Cc@Ec@Ec@Gw@Ec@Gu@Cc@Ec@Ea@Cc@Ec@Gs@Ec@Ca@Ea@Ca@Ea@Ea@C_@Ea@E_@C_@E_@E_@E_@E_@E_@?GCWE_@E_@Ea@E_@E_@Ea@Ea@Ea@Gu@Gc@Ee@Ee@Ge@Ee@Ge@Iy@Ec@Ee@Iw@Ee@Gc@Ec@Ec@Is@Ea@Ea@Ea@E_@Go@E_@C]E]E]C_@E_@Ea@Ea@E_@Iq@Ea@Ea@Ea@Ea@Gq@Ea@Ea@Ec@Ea@Ea@Ea@Ec@Ga@Ec@Ea@Ec@Ea@Ec@Ea@Ec@??Ea@Ec@Ea@Ga@Ec@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ga@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Is@Ea@Ec@Ea@Ec@Ea@Ec@Ea@Gc@Ec@Ec@Ee@Iw@Ge@Ee@Ec@Ee@Gc@Eg@Gg@Gk@Eg@Gi@Gg@Ee@Ge@Gc@Gc@Ga@I_@Ia@G_@I_@I_@I]G_@GWAGI]G]I]G]I]G[I]G[G[I[EWI[G]GYI]EYI[I_@Ic@Ic@Ka@Ic@Ic@Ka@Ia@Ic@Ka@Ia@Ic@Ka@I_@Ic@K_@Ia@GYAGIa@K_@Ia@G]I]I[G[G[GYGYGYG[I[G]m@qCKc@Ic@Kc@Ke@Ic@Kc@Ic@Kc@Kc@Ic@Ke@Ia@Kc@Ic@Ka@Ic@Ia@Ka@Ia@Ia@Ka@Ic@Ia@Ka@Ia@I_@G]I[GY?AGYGYI[G[G]I]I]I_@I_@I_@Ia@I_@I_@Ia@I]I_@G_@I_@I]I_@I]I_@G]I]I_@I_@I_@I_@I_@Ia@I_@Ia@Kc@Ic@Ka@Ic@Kc@Ie@Kc@Kc@Ic@Kc@M_@K_@K]M[K]K]M]K]M]K]M]K_@M]K]M]K_@M]K]M_@M]K_@CGIUK[IYIUM_@K]M]K[K]IWKWI[M]K]M]K]M[MYMYMWOWMYOWOYO[MYQYOYO[O[OYO[OYQ[OYO[OYOYO[OYOWOYOWMWOWOWMUOWOWOUOWOUMWOWOUOWOWOWQYOYQWOWMUOUMUMUOUMUOWOWYe@QYOYi@aAQWOYOWMUOWMUMUMUMUOUMWOWOYOWOWOUMWMUOUMUMWCCKQOWMWOWOWOYQYOWOYQYO[QYOYQYQYOYQYO[QYOYQYO[QYOYOYQYOYQYOYOYQYO[OYQYOYOYQYOYQYOYO[QWO[OYQYOWOYOYOYOW_@q@MWMWOWOYO[OYOYQ[OYO[OYOYO[OYOYOYQYOYOWOYQWOWOWQYOWQYQW??OWQYOWOWQYQWQYQYQ[Q[S[S[S]Q[SYQ[QYQYOYOYOWMYOWMWOYOYO]Q]Q[O]Q[O[OYO[OYOWMYMWOWMWMWOYO[Q]Q]Q]Q]Q]Q]Q[O]Q[O]Q[Q[O[O[Q[oD}GEIIOQYO[OYOYQYOYOYOYOYQYOYOYOYOYOYOYOWOWMYOWOWOYOWMYOWOYOYQYOYO[OYO[Q[OYOYOYOYMYOYOYOYQ[O[OYQ[OYOWOYOWOWOYOYQYO[QYOYQYOYOWOYOYQYOYOYQYOYOYOYQ[QYQ[OYO[QYO[Q]Q[Q[Q]Q[O[Q[MWU_@Q]O[Q[QYO[Q]Q[Q[Q[O[Q[Q[O[Q[Q[OYQ[Yi@OYO[QYO[Yi@O[Q[Q]Q[OYCEISMUOYOYKUMSMWKUOUMYQ[KSKSMUMUOUMUOSOSOSQQOQQSQSSUSUUWSWUWSWSWQYQWQYQYOYOYOWOYOYMYOWOYOYOYO[QYQ[O[OYOYOYOYQYO[MUACQ]QYO[OYMWOWKUMSO[KSMUMUMWOWMWOWMYOWMYOWOYOYOWOYOYO[QYQYSYSWSWSUUSSSUQUQWQWOYO[M[KYI[IYE[EYCYCsA?k@DOBQBYD]HYJeA`@SHq@Z}DdBmBz@k@Vo@VmA\e@L[HYFc@Ha@F[Do@H_AL]DWDUBWDWBWDWBUDWBYDWBWDYBYBYB[?Y@[A[A[C[C[E]G]I]I]M]M]OqAw@g@]WUYWUWWWUYSWQUCCUWUWSUUUUSUQUQUOUMUMUKWKWIUGWGWEWEWCWC]A{ADWBUDWDWDWHUFWHWHWHWFUHWHWHWHWHUHWFWHWHWHWFYFu@PUDUBUBWB}BJY@Y?[?[AYA[A[A[A[A[C[A[A]A]A[A_@C]A]A[A[A[AYAYAYAWAWAUAUAWAYAWAWAWAYAWAWAgCIWA_HWYAYAWAYAYAWAYAYAWAYAYAWAYAYAYAWAYAYAYA}@EYAYAYAWAYAYAq@Ce@Cg@AWAYAYAe@CWAYAe@AWAYAYAc@AY?W@Y?WBW@YBWBWDYDWDWDWFWHWFWHWJWHULWJWLULWLUNUNUNUPUPUPSRURURSTURSTUTURUTUTUTSRUTSRSRUTURUTUVWTYVYXWTYRYNYNWJYHYHYFe@FWBWBYBWDYBYBYDWBU@S?YAUCOCUEUGWIQISKQKSMQOQOQOSQQQQQOSQSOUOUMYOYM[M]K]K]I_@G[G]Ea@Ea@Ec@Ce@Ce@Ag@?e@@e@@a@B_@Ba@B_@D_@B_@Da@B_@Da@B_@D_@B_@Da@Ba@Dc@De@Be@De@Be@Bg@Be@@c@Be@@e@@c@@c@@c@?c@@c@?c@?e@?e@Ae@?c@Ae@Ac@Ac@Ac@Aa@Ac@?_@Aa@Aa@?c@?c@?c@?e@?e@?e@@c@@c@@c@@c@@a@@a@Ba@@a@Bc@Bc@De@Bc@De@Dc@Da@Dc@Da@Da@Fa@Da@Fc@Dc@Fc@Dc@Fa@Da@Da@Fa@D_@Dc@Fc@Da@Fe@Dc@D[@IFc@Da@Fa@Da@Da@D_@D_@Fa@Da@Da@Fc@Da@Fe@Fc@Da@Dc@Fa@Da@Da@Fa@Da@Fc@Da@Fc@Dc@Fc@De@Fc@Fc@Dc@Fa@Dc@Da@Fa@Dc@Fa@Dc@Fc@Dc@Fe@Fc@De@Fc@Fc@Da@Fa@Da@Fc@Ha@Fa@Hc@Ja@Ha@Jc@Ja@J_@J_@J_@J]L[J]L]L[N]N]L]N[N[L[Ti@N[N[L]N[N]N]N[N]N]N]N]N[N]L[N[N]N[L]N]P]N]N]N_@N]N[N]N[L[LYN[LYLYLYLYL[L[N[N]L]L_@L]L]J_@J]H]J_@H]H]F_@Ha@Fa@Ha@Da@Fc@Da@Da@Da@Bc@Dc@Be@Be@@g@@e@@e@@g@?e@?g@Ae@?e@Ag@Ce@Ac@Ce@Cc@Ec@Ca@Ec@E_@Ea@E_@G_@Ea@E_@E_@Ga@Ea@Ga@Ea@Ec@Ga@Ec@Ga@Ec@Ga@Ec@Gc@Ec@Ga@Ec@Ga@Ea@Ga@Ea@Gc@Ea@Gc@Ec@Gc@Ea@Gc@E_@Ea@Ga@E_@Ec@Ga@Ea@Ga@Ec@Ga@Ec@Gc@Ea@Gc@Ec@E_@Ga@E_@Ea@Ga@Ea@Ea@Ga@Ea@Gc@Ea@Gc@Ec@Gc@Ec@Gc@Ge@Ee@Ee@Ee@Gc@Ec@Cc@Ea@Ec@Ec@Gc@Ee@Eg@Eg@Gg@Ee@Ee@Ee@Ge@Eg@Ec@Ee@Ee@Ge@Ee@Ee@Ee@Ee@Ee@Gc@Ee@Ee@Ec@Ee@Ec@Ec@Ec@Ec@Ec@Ec@Ea@Ea@E_@E_@E]EYC[E[Ea@Ga@Ea@Ea@E_@E_@E]E]E[E[C]sBySEc@Ea@Cc@Ee@CYC[CWEa@C_@C]Ea@Ca@Ec@Ec@Ca@Ga@Ea@Ga@Ga@I_@I_@I]I_@K]K]K]K]K]K]K]K]M]K]K]K]K_@M]K]K_@M]K_@K[K]M[KYKYMYKYMWMYMWMWMYOWOYO[OYQ[O[O[OYMUMUKUMUMUKUMUMUKUMSKWMUMWMWIYG[E_@E_@Ca@Ea@C_@Ea@E_@Ea@Ea@E_@Ea@G_@E_@Gc@Ga@E_@E_@E]E[EYEYEYE[E[E[E]C]?_@?]B[B[FYH[JWLWLSLMTQTMTIRGVIHCl@Sl@UdBk@TGLE\Ij@IPAZCT?\@N@N@PB`@DP@VBN?X?R?VAJAPCPETEl@OlCo@p@OdAYh@M';
const _h9Encoded = r'ca}`Hw`ysBKgBEo@AM?OAK?MAM?OAQ?Q?OAS?SASAQAUCi@IyA?AIwAMuBA[Ca@Ca@Es@Eq@Aa@Eu@Ca@Es@Eo@A]C_@C_@C_@C_@Cq@C_@Eq@Eq@Aa@Ca@Eq@Ca@Ca@Eq@Aa@Ca@Ca@Es@Cc@Ca@Cc@Eu@Ca@Eu@Ca@Aa@Eq@C]C]A]C_@Ck@C_@Em@?GAUEo@C]A_@Em@Eo@C_@C_@Eo@C_@E_@C_@Ca@Gq@Ca@Es@Ec@Ca@Cc@Cc@Aa@SeHCc@Ac@Ac@Ac@Ac@Ac@Cc@Ac@Au@Cc@Aa@As@Aa@Cs@Cs@Aa@Cc@Cq@Cc@Ca@Ca@Ec@Gs@Ca@Gu@Ea@Ec@Cc@Gs@Ec@Ec@Cc@Ec@Ec@Gw@Ec@Gu@Cc@Ec@Ea@Cc@Ec@Gs@Ec@Ca@Ea@Ca@Ea@Ea@C_@Ea@E_@C_@E_@E_@E_@E_@E_@?GCWE_@E_@Ea@E_@E_@Ea@Ea@Ea@Gu@Gc@Ee@Ee@Ge@Ee@Ge@Iy@Ec@Ee@Iw@Ee@Gc@Ec@Ec@Is@Ea@Ea@Ea@E_@Go@E_@C]E]E]C_@E_@Ea@Ea@E_@Iq@Ea@Ea@Ea@Ea@Gq@Ea@Ea@Ec@Ea@Ea@Ea@Ec@Ga@Ec@Ea@Ec@Ea@Ec@Ea@Ec@??Ea@Ec@Ea@Ga@Ec@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ga@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Ea@Ea@Ea@Ec@Ea@Ea@Is@Ea@Ec@Ea@Ec@Ea@Ec@Ea@Gc@Ec@Ec@Ee@Iw@Ge@Ee@Ec@Ee@Gc@Eg@Gg@Gk@Eg@Gi@Gg@Ee@Ge@Gc@Gc@Ga@I_@Ia@G_@I_@I_@I]G_@GWAGI]G]I]G]I]G[I]G[G[I[EWI[G]GYI]EYI[I_@Ic@Ic@Ka@Ic@Ic@Ka@Ia@Ic@Ka@Ia@Ic@Ka@I_@Ic@K_@Ia@GYAGIa@K_@Ia@G]I]I[G[G[GYGYGYG[I[G]m@qCKc@Ic@Kc@Ke@Ic@Kc@Ic@Kc@Kc@Ic@Ke@Ia@Kc@Ic@Ka@Ic@Ia@Ka@Ia@Ia@Ka@Ic@Ia@Ka@Ia@I_@G]I[GY?AGYGYI[G[G]I]I]I_@I_@I_@Ia@I_@I_@Ia@I]I_@G_@I_@I]I_@I]I_@G]I]I_@I_@I_@I_@I_@Ia@I_@Ia@Kc@Ic@Ka@Ic@Kc@Ie@Kc@Kc@Ic@Kc@M_@K_@K]M[K]K]M]K]M]K]M]K_@M]K]M]K_@M]K]M_@M]K_@CGIUsDeL[o@We@W_@??yAmB_@[o@c@IC}Du@IAE?K?wAHyAHyCN]B]B[@[B[Bg@Be@Dg@Bc@Bc@Ba@Ba@B??i@Di@HSDWHWHe@TULWPa@\MN_@b@]d@_N|QsBtCs@lAq@zA{@vBO`@Ob@Yr@Qb@Ob@Qb@Qb@Qb@Qd@Qd@Ob@A?Qd@Qd@Qd@Qf@aAfCQd@[x@Sf@Qd@Qf@Sd@Qd@Qf@Qd@Sd@Qd@Qd@Qd@Qd@Qb@Qd@Qb@Qd@Ob@Sb@Q`@S`@U\UXWVWTYRWNYJg@Ng@F[@Y?g@GQCYG[KWMYOWSUUUWUYS[S]Qa@Sa@Si@Uk@Um@Wm@Um@Uk@Si@Uk@Si@Sg@Sg@Sg@Qe@Qe@Se@Qe@Sg@Si@Sg@Si@Se@Qg@Se@Si@Si@Sg@Sg@Sg@Qe@Qe@Sg@Se@Si@Si@Si@Ui@Si@Uk@Si@Ui@Sk@Uk@Si@Uk@Uk@Si@Si@Ui@Qg@Se@Qe@Qe@Qc@Qa@Oa@Qc@Oc@m@wASi@Ys@Um@]eAS{@Oy@MmAIuA?o@?[B}@HiAHo@D[J{@NgA^yC';
const _tram1Encoded = r'{zeaHmtcsBBCnAeBDEHM@CVc@JU`@k@r@eA^g@`@q@HOXk@~@eBj@iAR]~@uANQHMJO@Af@o@nDgFDG?A?@LOFIDIXe@pDaG~@aBBEn@cABG^o@pB{DlBmDFKFIHOHQv@uAv@uAAC@B@Cd@{@FOJWHQFQFKHSXq@Tm@Vw@J[Ja@Py@Lq@Hi@f@gEJiAF]BUD[Je@Nu@Hi@Hu@??CAB@Fm@H}@BWdGu`@zAmKxEs[H_@Li@DWFUDWBUFa@CAB@?AJw@Hs@NkAt@yEXwAZiA^mAZy@Zq@Zq@dAkBfAmB`@o@zAwBzA}BCCBB?AXa@`@m@T]NWJMNSFKT_@b@}@hA_CTc@HMFOP[Ve@xAuC\m@NYP_@rA{BAE@DjAwBl@gAJSLUnAuCl@iAvAiCv@yA^o@zCuF`@s@JQfAqBd@y@xAoC@CAC@B^s@DEFMFKp@gAbAkBt@yAf@}@x@}AtAcC~AkC@EAC@Bl@eAl@iApA}BvGeM|AqC`BwC~AkCx@sAnBiDCCBBBE~AmCnBgDz@yAlAqBf@y@|@yA@CAA@@HON[NWN[dAcBhBcDjAoBf@y@zAsB\k@j@}@z@yAR[AC@BLU\m@fBwClAoB~AwB\e@HIJKFG?A@A@AVS|AsBAC@B?ApAeB~BwCdByBnA}ArAaBhB{BhAuArA{AxAgBAE@D@ALQLKPQTSp@k@pA{@dEuC|CuBpBwA\W????d@[h@]LGZO@?HEFCLCNE\Gb@?NAtBYd@IPCBAfC[?G?FgCZC@WG[FuATtAUZGVFBAlC]NCTEVGTIJAfDi@|IuAtAQr@E`@AV?bB@T??G?FP@|AAnI?`@?d@@nELv@BvABvBHJ??I?HJ?n@?H?H?F@B?B?B?F?B?F?L@H?nCDr@@\BPDPFTHTHlBr@hAb@XLlAf@x@b@D@FDDBVNZPtBxA@EADRPVRLJ`A|@hDtCjI`H`@\h@d@LNTVVTpBzA@@@EADHFjBvAvDrC`DzBdDdCXTlDjCx@n@NHh@Z^PVR|AfA@EAD@?VRDDFDBDDD^h@BDBBDDDDBBDDFDzAhAh@`@FDDDDDFDDDFDDFFDFDhEbDh@b@TVJNJL`@l@RZN\LXBCCBBDVr@xGzXv@`DLj@DTFVDVRtAJfAF|@@LD?E?B^B^@\HzCJhDDxARbCPrBl@~D@FB?C?DPDRDVBLFXJ\Xx@Lb@TnARfAR|AHn@Fj@PnBFjA@d@@^FnEB`B@pAApBA|AK`CUbHAF?H?@Cp@?b@?d@?b@?b@?`@@`@?`@@`@?@B?C?@^D|@@d@@dA?Z?Z?Z?X?ZArA_@~g@ApAAr@Ap@CfBEtAEv@Cz@KrBEx@GdAE|@EdA?BB@CAAXAb@C|@CfAA`AAbACp@Ap@An@Cr@Aj@Cl@En@Cp@G|@Ez@Ef@ANAPAZE`@CVCVCTE`@G\Eb@K`AB@CA??Gp@Ix@Gt@Eb@E\EZIl@ALWbBCNALAN?J@N?LBJ@LBLDJDLDFDFDFFFHFHDH@HBb@J~FnAHBHBTDD@FBfB^p@Nr@N|A\@EADLB^FZFv@Pt@Np@Lp@Ht@Hz@Hf@Fd@FZFtAXf@Lj@NRF`@Jt@RlB`@@EADF@NBJFFHFFBFDJBH@F@F@H@H?F?HAF?Hq@vJCVe@~G?DCXCb@AB?@?BCPCPAFAD?B????AHGbAATAA@@IhAHBICAF?@ARCP?LANAJ?NAJ?H?LANCZQhCWnDMnBKvAIfAEf@E`@CXs@lKY`Ea@fGEZC`@CXEVEh@S|C?@B@CAAB?L{AlTB?C?APEj@ATATC|@GhAGr@Ev@Q~BCd@_A|MAH?F?F?F?D?B@F?B@HDNBHHNDDBBD@B@FBFBFBB@B@J@PB~@LD@AD';
const _tram2Encoded = r'ez~`HqhgsBAB\PLFB@NFPJB?DBB@B@B@B@B@B@B@B?nBd@B?NB|Cr@|Bh@FBD@F@F@F@D@F@F@pAJp@F??@IAHz@HB?FAJAFAFCDADGBEDM@K@QFoA@QBOBE@C@CJIFC@?LCFAD?hDGzCGhBED@D@JDHDBDBBBF@F@FBH?DB\@PB?C??FLdCB^BRBLBHBFDDBBD@BBF@dAJB@DBBBBBBBBBBH@DBF?DFnA?D@HBJBF@@@BBFDBLDN?d@EdAKp@Kd@Gr@IlMaCLENGAG@F@AVOFE^SPINIRGTIPIJGPODEPe@TYRGRCZBZLLDV@ZEdBg@HEb@Et@DFAAC@B@?BAp@O~@_@jBw@hDcB|@c@?C?B@Al@[VMrBiAjDwBTOdE{Cp@k@TONCLCZETMvAcAfAs@`@YBAAE@D`Aq@b@c@d@k@h@q@bCmDbBgC\i@fCoD@BAC^g@NWfAaBj@w@jA_BFICEBDBEj@k@|CwDdCaDBEFI@??B?CBEJQFMN]Ja@FWJi@Fa@BQ?ED_@Fe@DYHYJULWbA}AjB{CbA_BFKLQDGCGBF@AXc@Xc@jByCp@gAb@m@PSTWRSX[nCsC@ArAyABA@BACr@w@TWVWj@m@RUPWJY\yADQ@ADMJUT[RU\Sd@ObAYzF{A`Bc@bAYNEJECKBJDADCTKf@]p@k@@ANOHGf@a@PQHIVSLItAgARO???A?@TQn@e@`DeCHGnDqCpAeAVS@?@BACbAy@^[tAgAfDkC~@k@jBgAJGPKbAu@VOJK@Ah@c@b@]';
const _tram4Encoded = r'sw}`HkzbsB@q@?S?UESEOAGIQGMGMKQGGCEQSGIa@e@[a@EEsAaB@EADA?IKCEs@w@aBsB_@e@[e@[i@Si@_@oAQi@c@_Be@uBWoAS}@CMg@wBAEC@BAEMGYGUM_@Uy@a@}Ag@iBAGCICIACCCCGIQEIQUIGSQKEeDqAo@WEAOGYQyDwBGCKIGKGOCM?CCO?C?????O?oCCmAAKCsC?gAA_A?GF?G??O?i@AuAAs@IuNAc@AwC?YBQDSh@uBBMECDB@GzCgMHYj@}BFUDODMBKBKFSBGBGDM@C@GHWJ_@Ns@FY?EAA@@DSHe@DOH_@No@^}Af@mBJa@vAwFJ]bAaEH]H[x@iDx@gDXcA@EBMBGDKBG?CDKDMRk@z@_CDGDHEI@EFM@ADGDKHMFIFIxBwCJQLQJQDEFMJMtCsEHOLS|F{Jv@kA^o@HKNSR[jAiB????DGDIJSVc@PYn@aAHKXc@nG{HDEPUJKrA}ADE@ADHEI`EmEDE`CmCt@y@n@u@BARSNMRQdBgA??@DAENIZUtDgCBCHCHCv@QfBa@~@SRERCRAVCXCZGlB]@LAMREPAZCv@IZCrJc@NApBOL?B?~AJF@AL@MF?TBhIv@L?N@bDXB??H?IP@P@R@bJt@J@zCTv@Ff@H?L?MHBNBJBJDXLTJVH~Ab@`AXXHb@JZHzAf@vCz@JBh@P~Bp@D@AH@IJFp@Xp@`@n@`@f@\\\X\PZRd@Rl@Rh@J^z@lB@?A?@@T`@JZN^Pf@jB~EnAfD~BbGzB`GTn@Tl@Z|@`@hAN\v@tBBCCBLXJTDJFJR^HNFN?@?A?@P`@b@fAtBrFN^L^DHPf@FNBF^~@`AhCTl@Rh@Tl@JVHZFPNd@r@hBXt@??@AA@FRHTBNBNBRBX@X?XA^AZg@vJC\OnCAREv@?HADO|CAN@?';

final m1RoutePoints = decodePolyline(_m1Encoded);
final m2RoutePoints = decodePolyline(_m2Encoded);
final m3RoutePoints = decodePolyline(_m3Encoded);
final m4RoutePoints = decodePolyline(_m4Encoded);
final h5RoutePoints = decodePolyline(_h5Encoded);
final h6RoutePoints = decodePolyline(_h6Encoded);
final h7RoutePoints = decodePolyline(_h7Encoded);
final h8RoutePoints = decodePolyline(_h8Encoded);
final h9RoutePoints = decodePolyline(_h9Encoded);
final tram1RoutePoints = decodePolyline(_tram1Encoded);
final tram46RoutePoints = decodePolyline(_tram4Encoded);
final tram2RoutePoints = decodePolyline(_tram2Encoded);

// --- Railway Mainline Corridors (Dense, Track-Following Coordinates) ---

/// Mainline 1: Budapest – Győr – Hegyeshalom (1st mainline corridor).
const railwayLine1Points = <LatLng>[
  LatLng(47.500400, 19.083800), // Keleti pu
  LatLng(47.492000, 19.098000), // Ferencváros elágazás
  LatLng(47.469000, 19.083000), // Ferencváros
  LatLng(47.468000, 19.064000), // Déli összekötő Duna-híd
  LatLng(47.464600, 19.021500), // Kelenföld
  LatLng(47.452000, 18.966000), // Budaörs
  LatLng(47.448500, 18.915000), // Törökbálint
  LatLng(47.468000, 18.825000), // Biatorbágy
  LatLng(47.498000, 18.742000), // Herceghalom
  LatLng(47.488000, 18.655000), // Bicske alsó
  LatLng(47.485000, 18.638000), // Bicske
  LatLng(47.525000, 18.520000), // Szár
  LatLng(47.551000, 18.495000), // Szárliget
  LatLng(47.568000, 18.435000), // Felsőgalla
  LatLng(47.585000, 18.397000), // Tatabánya
  LatLng(47.618000, 18.375000), // Vértesszőlős
  LatLng(47.640000, 18.345000), // Tóvároskert
  LatLng(47.652000, 18.326000), // Tata
  LatLng(47.728000, 18.258000), // Almásfüzitő
  LatLng(47.734000, 18.232000), // Almásfüzitő felső
  LatLng(47.738000, 18.175000), // Szőny
  LatLng(47.746000, 18.125000), // Komárom
  LatLng(47.712000, 18.012000), // Ács
  LatLng(47.702000, 17.885000), // Nagyszentjános
  LatLng(47.701000, 17.765000), // Győrszentiván
  LatLng(47.688000, 17.662000), // Győr-Gyárváros
  LatLng(47.683000, 17.635000), // Győr
  LatLng(47.698000, 17.545000), // Abda
  LatLng(47.725000, 17.485000), // Öttevény
  LatLng(47.765000, 17.412000), // Lébény-Mosonszentmiklós
  LatLng(47.815000, 17.355000), // Kimle-Károlyháza
  LatLng(47.868000, 17.274000), // Mosonmagyaróvár
  LatLng(47.892000, 17.205000), // Levél
  LatLng(47.915000, 17.155000), // Hegyeshalom
];

/// Mainline 30a + 30: Budapest – Székesfehérvár – Siófok – Balaton – Keszthely.
const railwayLine30aPoints = <LatLng>[
  LatLng(47.500000, 19.025300), // Déli pu
  LatLng(47.464600, 19.021500), // Kelenföld
  LatLng(47.445000, 19.035000), // Albertfalva
  LatLng(47.426000, 19.038000), // Budafok
  LatLng(47.405000, 19.022000), // Kastélypark
  LatLng(47.391000, 18.995000), // Tétényliget
  LatLng(47.382000, 18.928000), // Érd alsó
  LatLng(47.375000, 18.855000), // Tárnok
  LatLng(47.318000, 18.788000), // Martonvásár
  LatLng(47.288000, 18.752000), // Baracska
  LatLng(47.265000, 18.725000), // Pettend
  LatLng(47.242000, 18.685000), // Kápolnásnyék
  LatLng(47.235000, 18.652000), // Velence
  LatLng(47.221000, 18.645000), // Velencefürdő
  LatLng(47.198000, 18.625000), // Gárdony
  LatLng(47.185000, 18.605000), // Agárd
  LatLng(47.172000, 18.562000), // Dinnyés
  LatLng(47.185000, 18.428000), // Székesfehérvár
  LatLng(47.165000, 18.398000), // Székesfehérvár-Repülőtér
  LatLng(47.125000, 18.368000), // Szabadbattyán
  LatLng(47.085000, 18.315000), // Kiscséripuszta
  LatLng(47.058000, 18.285000), // Polgárdi-Tekerespuszta
  LatLng(47.042000, 18.245000), // Lepsény
  LatLng(46.975000, 18.165000), // Balatonvilágos
  LatLng(46.938000, 18.115000), // Szabadisóstó
  LatLng(46.921000, 18.092000), // Szabadifürdő
  LatLng(46.908000, 18.055000), // Siófok
  LatLng(46.895000, 18.028000), // Balatonszéplak felső
  LatLng(46.885000, 18.005000), // Balatonszéplak alsó
  LatLng(46.881000, 17.968000), // Zamárdi felső
  LatLng(46.878000, 17.945000), // Zamárdi
  LatLng(46.865000, 17.915000), // Szántód
  LatLng(46.852000, 17.882000), // Balatonföldvár
  LatLng(46.835000, 17.835000), // Balatonszárszó
  LatLng(46.812000, 17.785000), // Balatonszemes
  LatLng(46.792000, 17.725000), // Balatonlelle felső
  LatLng(46.785000, 17.695000), // Balatonlelle
  LatLng(46.775000, 17.655000), // Balatonboglár
  LatLng(46.762000, 17.585000), // Fonyódliget
  LatLng(46.748000, 17.552000), // Fonyód
  LatLng(46.735000, 17.518000), // Bélatelep
  LatLng(46.715000, 17.478000), // Balatonfenyves
  LatLng(46.705000, 17.385000), // Balatonmáriafürdő
  LatLng(46.702000, 17.315000), // Balatonberény
  LatLng(46.692000, 17.295000), // Balatonszentgyörgy
  LatLng(46.712000, 17.265000), // Fenékpuszta
  LatLng(46.765000, 17.248000), // Keszthely
];

/// Mainline 70: Budapest – Vác – Szob (Danube Bend corridor).
const railwayLine70Points = <LatLng>[
  LatLng(47.510900, 19.056900), // Nyugati pu
  LatLng(47.531000, 19.086000), // Rákosrendező
  LatLng(47.545000, 19.095000), // Istvántelek
  LatLng(47.562000, 19.088000), // Rákospalota-Újpest
  LatLng(47.615000, 19.125000), // Dunakeszi alsó
  LatLng(47.635000, 19.135000), // Dunakeszi
  LatLng(47.655000, 19.142000), // Dunakeszi-Gyártelep
  LatLng(47.682000, 19.140000), // Alsógöd
  LatLng(47.695000, 19.142000), // Göd
  LatLng(47.715000, 19.145000), // Felsőgöd
  LatLng(47.735000, 19.148000), // Sződ-Sződliget
  LatLng(47.762000, 19.142000), // Vác-Alsóváros
  LatLng(47.778000, 19.135000), // Vác
  LatLng(47.822000, 19.035000), // Verőce
  LatLng(47.828000, 19.015000), // Kismaros
  LatLng(47.785000, 18.958000), // Nagymaros-Visegrád
  LatLng(47.792000, 18.945000), // Nagymaros
  LatLng(47.785000, 18.925000), // Dömösi átkelés
  LatLng(47.798000, 18.908000), // Zebegény
  LatLng(47.812000, 18.885000), // Szob alsó
  LatLng(47.818000, 18.868000), // Szob
];

/// Mainline 100a + 100: Budapest – Szolnok – Debrecen – Nyíregyháza.
const railwayLine100aPoints = <LatLng>[
  LatLng(47.510900, 19.056900), // Nyugati pu
  LatLng(47.513000, 19.098000), // Zugló
  LatLng(47.487000, 19.128000), // Kőbánya alsó
  LatLng(47.464400, 19.149200), // Kőbánya-Kispest
  LatLng(47.448000, 19.185000), // Pestszentlőrinc
  LatLng(47.441000, 19.205000), // Szemeretelep
  LatLng(47.432000, 19.228000), // Ferihegy
  LatLng(47.408000, 19.268000), // Vecsés
  LatLng(47.395000, 19.288000), // Vecsés-Kertekalja
  LatLng(47.381000, 19.345000), // Üllő
  LatLng(47.365000, 19.395000), // Hosszúberek-Péteri
  LatLng(47.352000, 19.442000), // Monor
  LatLng(47.315000, 19.505000), // Monorierdő
  LatLng(47.285000, 19.555000), // Pilis
  LatLng(47.245000, 19.615000), // Albertirsa
  LatLng(47.218000, 19.685000), // Ceglédbercel-Cserő
  LatLng(47.195000, 19.742000), // Budai út
  LatLng(47.178000, 19.795000), // Cegléd
  LatLng(47.185000, 19.995000), // Abony
  LatLng(47.168000, 20.180000), // Szolnok
  LatLng(47.175000, 20.315000), // Szajol
  LatLng(47.182000, 20.425000), // Törökszentmiklós
  LatLng(47.215000, 20.555000), // Fegyvernek-Örményes
  LatLng(47.225000, 20.765000), // Kisújszállás
  LatLng(47.315000, 20.915000), // Karcag
  LatLng(47.318000, 21.112000), // Püspökladány
  LatLng(47.355000, 21.275000), // Kaba
  LatLng(47.445000, 21.405000), // Hajdúszoboszló
  LatLng(47.472000, 21.505000), // Ebes
  LatLng(47.521000, 21.625000), // Debrecen
  LatLng(47.545000, 21.655000), // Debreceni Csapókert
  LatLng(47.585000, 21.685000), // Apafa
  LatLng(47.645000, 21.675000), // Bocskaikert
  LatLng(47.715000, 21.685000), // Téglás
  LatLng(47.805000, 21.695000), // Újfehértó
  LatLng(47.955000, 21.718000), // Nyíregyháza
];

/// Mainline 80a + 80: Budapest – Hatvan – Füzesabony – Miskolc.
const railwayLine80aPoints = <LatLng>[
  LatLng(47.500400, 19.083800), // Keleti pu
  LatLng(47.492000, 19.128000), // Kőbánya felső
  LatLng(47.498000, 19.172000), // Rákos
  LatLng(47.495000, 19.225000), // Akadémiaújtelep
  LatLng(47.498000, 19.255000), // Rákosliget
  LatLng(47.497000, 19.278000), // Rákoscsaba-Újtelep
  LatLng(47.495000, 19.298000), // Rákoscsaba
  LatLng(47.493000, 19.338000), // Pécel
  LatLng(47.532000, 19.402000), // Isaszeg
  LatLng(47.565000, 19.378000), // Gödöllő-Állami telepek
  LatLng(47.593000, 19.358000), // Gödöllő
  LatLng(47.608000, 19.395000), // Máriabesnyő
  LatLng(47.635000, 19.465000), // Bag
  LatLng(47.658000, 19.488000), // Aszód
  LatLng(47.635000, 19.535000), // Hévízgyörk
  LatLng(47.632000, 19.565000), // Galgahévíz
  LatLng(47.615000, 19.615000), // Tura
  LatLng(47.668000, 19.678000), // Hatvan
  LatLng(47.685000, 19.785000), // Hort-Csány
  LatLng(47.688000, 19.925000), // Vámosgyörk
  LatLng(47.692000, 19.995000), // Adács
  LatLng(47.705000, 20.085000), // Karácsond
  LatLng(47.715000, 20.155000), // Ludas
  LatLng(47.718000, 20.215000), // Nagyút
  LatLng(47.728000, 20.265000), // Kál-Kápolna
  LatLng(47.742000, 20.418000), // Füzesabony
  LatLng(47.785000, 20.485000), // Szihalom
  LatLng(47.805000, 20.575000), // Mezőkövesd
  LatLng(47.845000, 20.675000), // Mezőkeresztes-Mezőnyárád
  LatLng(47.885000, 20.765000), // Csincse
  LatLng(47.935000, 20.815000), // Emőd
  LatLng(47.985000, 20.835000), // Nyékládháza
  LatLng(48.102000, 20.805000), // Miskolc-Tiszai
];

/// Mainline 140: Budapest / Cegléd – Kecskemét – Kiskunfélegyháza – Szeged.
const railwayLine140Points = <LatLng>[
  LatLng(47.510900, 19.056900), // Nyugati pu
  LatLng(47.513000, 19.098000), // Zugló
  LatLng(47.464400, 19.149200), // Kőbánya-Kispest
  LatLng(47.432000, 19.228000), // Ferihegy
  LatLng(47.352000, 19.442000), // Monor
  LatLng(47.178000, 19.795000), // Cegléd
  LatLng(47.115000, 19.805000), // Nyársapát
  LatLng(47.035000, 19.785000), // Nagykőrös
  LatLng(46.965000, 19.745000), // Katonatelep
  LatLng(46.912000, 19.698000), // Kecskemét
  LatLng(46.825000, 19.765000), // Városföld
  LatLng(46.775000, 19.785000), // Kunszállás
  LatLng(46.712000, 19.845000), // Kiskunfélegyháza
  LatLng(46.665000, 19.895000), // Selymes
  LatLng(46.625000, 19.925000), // Petőfiszállás
  LatLng(46.545000, 19.955000), // Csengele
  LatLng(46.475000, 19.985000), // Kistelek
  LatLng(46.415000, 20.015000), // Balástya
  LatLng(46.345000, 20.045000), // Szatymaz
  LatLng(46.305000, 20.075000), // Jánosszállás
  LatLng(46.275000, 20.095000), // Kiskundorozsma
  LatLng(46.262000, 20.135000), // Szeged-Rókus
  LatLng(46.241000, 20.145000), // Szeged
];

/// Mainline 40a + 40: Budapest – Pusztaszabolcs – Sárbogárd – Dombóvár – Pécs.
const railwayLine40Points = <LatLng>[
  LatLng(47.500000, 19.025300), // Déli pu
  LatLng(47.464600, 19.021500), // Kelenföld
  LatLng(47.445000, 19.035000), // Albertfalva
  LatLng(47.426000, 19.038000), // Budafok
  LatLng(47.405000, 19.022000), // Kastélypark
  LatLng(47.388000, 18.918000), // Érd felső
  LatLng(47.325000, 18.912000), // Százhalombatta
  LatLng(47.302000, 18.905000), // Dunai Finomító
  LatLng(47.248000, 18.895000), // Ercsi
  LatLng(47.165000, 18.825000), // Iváncsa
  LatLng(47.142000, 18.762000), // Pusztaszabolcs
  LatLng(47.075000, 18.695000), // Szabadegyháza
  LatLng(47.035000, 18.645000), // Sárosd
  LatLng(46.985000, 18.625000), // Nagylók
  LatLng(46.885000, 18.615000), // Sárbogárd
  LatLng(46.815000, 18.625000), // Rétszilas
  LatLng(46.785000, 18.605000), // Sáregres
  LatLng(46.755000, 18.555000), // Simontornya
  LatLng(46.705000, 18.475000), // Tolnanémedi
  LatLng(46.685000, 18.435000), // Pincehely
  LatLng(46.645000, 18.405000), // Belecska
  LatLng(46.605000, 18.415000), // Keszőhidegkút-Gyönk
  LatLng(46.575000, 18.395000), // Regöly
  LatLng(46.525000, 18.385000), // Szakály-Hőgyész
  LatLng(46.485000, 18.355000), // Dúzs
  LatLng(46.465000, 18.335000), // Csibrák
  LatLng(46.435000, 18.315000), // Kurd
  LatLng(46.415000, 18.235000), // Döbrököz
  LatLng(46.375000, 18.135000), // Dombóvár
  LatLng(46.315000, 18.132000), // Vásárosdombó
  LatLng(46.255000, 18.115000), // Sásd
  LatLng(46.215000, 18.095000), // Godisa
  LatLng(46.195000, 18.065000), // Bakóca
  LatLng(46.135000, 18.045000), // Hetvehely
  LatLng(46.105000, 18.012000), // Bükkösd
  LatLng(46.075000, 18.135000), // Cserkút
  LatLng(46.045000, 18.075000), // Bicsérd
  LatLng(46.065000, 18.155000), // Mecsekalja-Cserkút
  LatLng(46.068000, 18.232000), // Pécs
];

/// Budapest Connecting Railway (Déli pu – Kelenföld – Déli összekötő Duna-híd – Keleti pu).
const railwayConnectingLinePoints = <LatLng>[
  LatLng(47.500000, 19.025300), // Déli pu
  LatLng(47.464600, 19.021500), // Kelenföld
  LatLng(47.468000, 19.064000), // Déli összekötő Duna-híd
  LatLng(47.469000, 19.083000), // Ferencváros
  LatLng(47.500400, 19.083800), // Keleti pu
];

// --- Polyline Providers ---

/// Metro network polylines (M1, M2, M3, M4).
final metroPolylinesProvider = Provider<List<Polyline>>((ref) {
  return [
    Polyline(
      points: m1RoutePoints,
      strokeWidth: 3.5,
      color: const Color(0xFFFFD800),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: m2RoutePoints,
      strokeWidth: 3.5,
      color: const Color(0xFFE41F18),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: m3RoutePoints,
      strokeWidth: 3.5,
      color: const Color(0xFF005CA5),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: m4RoutePoints,
      strokeWidth: 3.5,
      color: const Color(0xFF439539),
      pattern: const StrokePattern.solid(),
    ),
  ];
});

/// Suburban rail network polylines (H5, H6, H7, H8, H9).
final hevPolylinesProvider = Provider<List<Polyline>>((ref) {
  return [
    Polyline(
      points: h5RoutePoints,
      strokeWidth: 3.0,
      color: const Color(0xFF821380),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: h6RoutePoints,
      strokeWidth: 3.0,
      color: const Color(0xFF86421B),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: h7RoutePoints,
      strokeWidth: 3.0,
      color: const Color(0xFFEE7203),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: h8RoutePoints,
      strokeWidth: 3.0,
      color: const Color(0xFFE52320),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: h9RoutePoints,
      strokeWidth: 3.0,
      color: const Color(0xFFE52320),
      pattern: const StrokePattern.solid(),
    ),
  ];
});

/// Major Budapest tram corridor polylines (1, 4-6, 2).
final tramPolylinesProvider = Provider<List<Polyline>>((ref) {
  return [
    Polyline(
      points: tram1RoutePoints,
      strokeWidth: 2.8,
      color: const Color(0xFFFFD800),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: tram46RoutePoints,
      strokeWidth: 2.8,
      color: const Color(0xFFFFD800),
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: tram2RoutePoints,
      strokeWidth: 2.8,
      color: const Color(0xFFFFD800),
      pattern: const StrokePattern.solid(),
    ),
  ];
});

/// Primary Hungarian railway mainline corridors (MÁV 1, 30a, 70, 80a, 100a, 140, 40, Körvasút).
final railwayPolylinesProvider = Provider<List<Polyline>>((ref) {
  const mavBlue = Color(0xFF004B93);
  return [
    Polyline(
      points: railwayLine1Points,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayLine30aPoints,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayLine70Points,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayLine100aPoints,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayLine80aPoints,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayLine140Points,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayLine40Points,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
    Polyline(
      points: railwayConnectingLinePoints,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
  ];
});

/// High-precision transit geometry utilities for track-snapping and direct trip geometries.
class TransitRouteGeometry {
  TransitRouteGeometry._();

  static final Map<String, List<LatLng>> _directTripGeometries = {};

  /// Registers direct vágánygeometria for a trip (e.g. from `trip.pattern.geometry` or OTP2 cache).
  static void registerDirectTripGeometry(String tripId, List<LatLng> points) {
    _directTripGeometries[tripId] = points;
  }

  /// Retrieves direct trip geometry if registered.
  static List<LatLng>? getDirectTripGeometry(String tripId) {
    return _directTripGeometries[tripId];
  }

  /// Clears registered direct trip geometries (useful for testing or cache invalidation).
  static void clearDirectTripGeometries() {
    _directTripGeometries.clear();
  }

  /// Defined railway mainline, suburban railway (HÉV), metro and tram corridors.
  static final List<List<LatLng>> railwayCorridors = [
    railwayLine1Points,
    railwayLine30aPoints,
    railwayLine70Points,
    railwayLine80aPoints,
    railwayLine100aPoints,
    railwayLine140Points,
    railwayLine40Points,
    railwayConnectingLinePoints,
    h5RoutePoints,
    h6RoutePoints,
    h7RoutePoints,
    h8RoutePoints,
    h9RoutePoints,
    m1RoutePoints,
    m2RoutePoints,
    m3RoutePoints,
    m4RoutePoints,
    tram1RoutePoints,
    tram46RoutePoints,
    tram2RoutePoints,
  ];

  /// Calculates geodesic distance between two points in meters using equirectangular projection.
  static double distanceMeters(LatLng a, LatLng b) {
    final dLat = (a.latitude - b.latitude) * 111139.0;
    final cosLat = math.cos((a.latitude + b.latitude) * (math.pi / 360.0));
    final dLon = (a.longitude - b.longitude) * 111139.0 * cosLat;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  /// Fits a coarse sequence of railway or HÉV station stops to real physical track coordinates.
  ///
  /// Intersects stop pairs against defined railway corridors, extracting dense track curve points
  /// instead of drawing straight lines across terrain.
  static List<LatLng> fitToRailwayTracks(List<LatLng> stops) {
    if (stops.length < 2) {
      return stops;
    }

    final result = <LatLng>[];

    void addPoint(LatLng p) {
      if (result.isEmpty || distanceMeters(result.last, p) > 40.0) {
        result.add(p);
      }
    }

    for (int i = 0; i < stops.length - 1; i++) {
      final stopA = stops[i];
      final stopB = stops[i + 1];
      final directDist = distanceMeters(stopA, stopB);

      List<LatLng>? bestTrackSegment;
      double bestScore = double.infinity;

      for (final corridor in railwayCorridors) {
        if (corridor.length < 2) continue;

        int closestA = -1;
        double minDA = double.infinity;
        for (int c = 0; c < corridor.length; c++) {
          final d = distanceMeters(stopA, corridor[c]);
          if (d < minDA) {
            minDA = d;
            closestA = c;
          }
        }

        int closestB = -1;
        double minDB = double.infinity;
        for (int c = 0; c < corridor.length; c++) {
          final d = distanceMeters(stopB, corridor[c]);
          if (d < minDB) {
            minDB = d;
            closestB = c;
          }
        }

        // Corridor must be closely aligned with both stations (max 2.5 km) and not degenerate
        if (minDA <= 2500.0 && minDB <= 2500.0 && closestA != closestB) {
          final startIdx = math.min(closestA, closestB);
          final endIdx = math.max(closestA, closestB);
          double corridorSegDist = 0.0;
          for (int k = startIdx; k < endIdx; k++) {
            corridorSegDist += distanceMeters(corridor[k], corridor[k + 1]);
          }

          // Reject corridor segments that take a wild detour (longer than 2.2x direct distance)
          if (corridorSegDist > directDist * 2.2 && corridorSegDist > 5000.0) {
            continue;
          }

          final score = minDA + minDB + (corridorSegDist - directDist).abs();
          if (score < bestScore) {
            bestScore = score;
            final segment = <LatLng>[];
            if (closestA < closestB) {
              for (int k = closestA; k <= closestB; k++) {
                segment.add(corridor[k]);
              }
            } else {
              for (int k = closestA; k >= closestB; k--) {
                segment.add(corridor[k]);
              }
            }
            bestTrackSegment = segment;
          }
        }
      }

      // Add departure stop
      addPoint(stopA);

      if (bestTrackSegment != null && bestTrackSegment.length > 1) {
        for (final p in bestTrackSegment) {
          addPoint(p);
        }
      }

      // Add arrival stop
      addPoint(stopB);
    }

    if (result.isEmpty || distanceMeters(result.last, stops.last) > 10.0) {
      result.add(stops.last);
    }

    return result;
  }
}
