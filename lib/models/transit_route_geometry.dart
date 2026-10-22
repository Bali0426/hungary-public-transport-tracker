import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// --- Metro Route Coordinates ---

const m1RoutePoints = <LatLng>[
  LatLng(47.496737, 19.050593), // Vörösmarty tér
  LatLng(47.497728, 19.054142), // Deák Ferenc tér
  LatLng(47.499937, 19.055655), // Bajcsy-Zsilinszky út
  LatLng(47.502305, 19.059161), // Opera
  LatLng(47.505023, 19.063233), // Oktogon
  LatLng(47.507238, 19.066529), // Vörösmarty utca
  LatLng(47.509261, 19.069544), // Kodály körönd
  LatLng(47.511342, 19.072662), // Bajza utca
  LatLng(47.514110, 19.076883), // Hősök tere
  LatLng(47.517407, 19.081481), // Széchenyi fürdő
  LatLng(47.519513, 19.091037), // Mexikói út
];

const m2RoutePoints = <LatLng>[
  LatLng(47.500450, 19.024604), // Déli pályaudvar
  LatLng(47.507533, 19.026097), // Széll Kálmán tér
  LatLng(47.506826, 19.038103), // Batthyány tér
  LatLng(47.505511, 19.045769), // Kossuth Lajos tér
  LatLng(47.497593, 19.053857), // Deák Ferenc tér
  LatLng(47.494825, 19.062457), // Astoria
  LatLng(47.497006, 19.070274), // Blaha Lujza tér
  LatLng(47.499683, 19.082881), // Keleti pályaudvar
  LatLng(47.500174, 19.106381), // Puskás Ferenc Stadion
  LatLng(47.501204, 19.120417), // Pillangó utca
  LatLng(47.502922, 19.135963), // Örs vezér tere
];

const m3RoutePoints = <LatLng>[
  LatLng(47.560437, 19.089760), // Újpest-központ
  LatLng(47.559146, 19.079567), // Újpest-városkapu
  LatLng(47.548374, 19.073019), // Gyöngyösi utca
  LatLng(47.538163, 19.069055), // Forgách utca
  LatLng(47.532171, 19.066471), // Göncz Árpád városközpont
  LatLng(47.524358, 19.063088), // Dózsa György út
  LatLng(47.517595, 19.060285), // Lehel tér
  LatLng(47.510828, 19.055952), // Nyugati pályaudvar
  LatLng(47.503670, 19.054513), // Arany János utca
  LatLng(47.497591, 19.054525), // Deák Ferenc tér
  LatLng(47.491820, 19.056789), // Ferenciek tere
  LatLng(47.489490, 19.061920), // Kálvin tér
  LatLng(47.484862, 19.072242), // Corvin-negyed
  LatLng(47.482872, 19.078425), // Semmelweis Klinikák
  LatLng(47.478365, 19.091071), // Nagyvárad tér
  LatLng(47.474913, 19.100672), // Népliget
  LatLng(47.470529, 19.111646), // Ecseri út
  LatLng(47.467939, 19.118838), // Pöttyös utca
  LatLng(47.465749, 19.126228), // Határ út
  LatLng(47.463443, 19.148764), // Kőbánya-Kispest
];

const m4RoutePoints = <LatLng>[
  LatLng(47.464255, 19.020587), // Kelenföld vasútállomás
  LatLng(47.465022, 19.033386), // Bikás park
  LatLng(47.473559, 19.046266), // Újbuda-központ
  LatLng(47.477310, 19.047645), // Móricz Zsigmond körtér
  LatLng(47.483039, 19.055036), // Szent Gellért tér - Műegyetem
  LatLng(47.486169, 19.058009), // Fővám tér
  LatLng(47.489245, 19.061938), // Kálvin tér
  LatLng(47.492760, 19.072489), // Rákóczi tér
  LatLng(47.496078, 19.077707), // II. János Pál pápa tér
  LatLng(47.500485, 19.081704), // Keleti pályaudvar
];

// --- HÉV Route Coordinates ---

const h5RoutePoints = <LatLng>[
  LatLng(47.506776, 19.039318), // Batthyány tér
  LatLng(47.515376, 19.039380), // Margit híd, budai hídfő
  LatLng(47.527303, 19.040168), // Szépvölgyi út
  LatLng(47.533964, 19.044643), // Tímár utca
  LatLng(47.539636, 19.047161), // Szentlélek tér
  LatLng(47.551903, 19.046243), // Filatorigát
  LatLng(47.556508, 19.045133), // Kaszásdűlő
  LatLng(47.567255, 19.048728), // Aquincum
  LatLng(47.575685, 19.048568), // Rómaifürdő
  LatLng(47.585948, 19.044932), // Csillaghegy
  LatLng(47.598091, 19.054599), // Békásmegyer
  LatLng(47.616165, 19.054920), // Budakalász
  LatLng(47.621692, 19.046912), // Budakalász, Lenfonó
  LatLng(47.628802, 19.043332), // Szentistvántelep
  LatLng(47.642749, 19.032657), // Pomáz
  LatLng(47.652191, 19.064901), // Pannóniatelep
  LatLng(47.661038, 19.075607), // Szentendre
];

const h6RoutePoints = <LatLng>[
  LatLng(47.466285, 19.077170), // Közvágóhíd
  LatLng(47.454906, 19.086556), // Kén utca
  LatLng(47.438416, 19.093425), // Pesterzsébet felső
  LatLng(47.423380, 19.105036), // Torontál utca
  LatLng(47.409938, 19.111832), // Ilonatelep
  LatLng(47.399538, 19.114655), // Rákócziliget
  LatLng(47.391812, 19.114963), // Karácsony Sándor utca
  LatLng(47.379898, 19.104976), // Dunaharaszti északi rész
  LatLng(47.366371, 19.092656), // Dunaharaszti felső
  LatLng(47.359892, 19.086130), // Dunaharaszti külső
  LatLng(47.344207, 19.050242), // Szigetszentmiklós
  LatLng(47.337095, 19.034336), // József Attila-telep
  LatLng(47.336444, 19.019615), // Szigetszentmiklós alsó
  LatLng(47.333635, 19.003776), // Szigethalom
  LatLng(47.330041, 18.993868), // Szigethalom alsó
  LatLng(47.321368, 18.983529), // Tököl
  LatLng(47.313477, 18.974254), // Szigetcsép
  LatLng(47.270231, 18.956263), // Szigetszentmárton-Szigetújfalu
  LatLng(47.227924, 18.946067), // Horgásztanyák
  LatLng(47.213582, 18.952953), // Angyalisziget
  LatLng(47.199808, 18.945066), // Ráckeve észak
  LatLng(47.175605, 18.941796), // Ráckeve
];

const h7RoutePoints = <LatLng>[
  LatLng(47.479179, 19.066433), // Boráros tér
  LatLng(47.469554, 19.070098), // Müpa - Nemzeti Színház
  LatLng(47.444476, 19.071612), // Szabadkikötő
  LatLng(47.431322, 19.067656), // Szent Imre tér
  LatLng(47.426802, 19.067283), // Karácsony Sándor utca
  LatLng(47.421171, 19.065803), // Csepel
];

const h8RoutePoints = <LatLng>[
  LatLng(47.502922, 19.135963), // Örs vezér tere
  LatLng(47.508500, 19.153800), // Rákosfalva
  LatLng(47.512600, 19.170500), // Nagyicce
  LatLng(47.512000, 19.182000), // Sashalom
  LatLng(47.511800, 19.197000), // Mátyásföld, repülőtér
  LatLng(47.514000, 19.208500), // Mátyásföld, Imre utca
  LatLng(47.516000, 19.216500), // Mátyásföld alsó
  LatLng(47.519435, 19.217338), // Cinkota
  LatLng(47.526627, 19.229403), // Ilonatelep
  LatLng(47.539065, 19.249034), // Kistarcsa, kórház
  LatLng(47.545832, 19.259801), // Kistarcsa
  LatLng(47.548442, 19.264069), // Zsófialiget
  LatLng(47.553433, 19.271377), // Kerepes
  LatLng(47.568488, 19.275036), // Szilasliget
  LatLng(47.595970, 19.271560), // Mogyoród
  LatLng(47.597338, 19.290352), // Szentjakab
  LatLng(47.595072, 19.340771), // Gödöllő, Erzsébet park
  LatLng(47.597505, 19.347599), // Gödöllő, Szabadság tér
  LatLng(47.598525, 19.356661), // Gödöllő, Palotakert
  LatLng(47.593341, 19.357787), // Gödöllő
];

const h9RoutePoints = <LatLng>[
  LatLng(47.502922, 19.135963), // Örs vezér tere
  LatLng(47.508500, 19.153800), // Rákosfalva
  LatLng(47.512600, 19.170500), // Nagyicce
  LatLng(47.512000, 19.182000), // Sashalom
  LatLng(47.511800, 19.197000), // Mátyásföld, repülőtér
  LatLng(47.514000, 19.208500), // Mátyásföld, Imre utca
  LatLng(47.516000, 19.216500), // Mátyásföld alsó
  LatLng(47.519435, 19.217338), // Cinkota
  LatLng(47.526364, 19.220986), // Cinkota alsó
  LatLng(47.532979, 19.212554), // Árpádföld
  LatLng(47.537404, 19.206185), // Szabadságtelep
  LatLng(47.545049, 19.225058), // Csömör
];

// --- Tram Corridors ---

const tram1RoutePoints = <LatLng>[
  LatLng(47.548796, 19.029376), // Bécsi út / Vörösvári út
  LatLng(47.545936, 19.033455),
  LatLng(47.541539, 19.039979),
  LatLng(47.539596, 19.045199), // Árpád híd
  LatLng(47.536322, 19.058867),
  LatLng(47.532255, 19.067313), // Göncz Árpád városközpont
  LatLng(47.530438, 19.070181),
  LatLng(47.526227, 19.076952),
  LatLng(47.523653, 19.080987),
  LatLng(47.519099, 19.088115), // Kacsóh Pongrác út
  LatLng(47.516814, 19.091406),
  LatLng(47.513835, 19.095758),
  LatLng(47.511333, 19.099141),
  LatLng(47.507184, 19.104022),
  LatLng(47.500966, 19.108091), // Puskás Ferenc Stadion
  LatLng(47.496271, 19.109134),
  LatLng(47.491216, 19.108982),
  LatLng(47.486260, 19.107530),
  LatLng(47.481801, 19.103611),
  LatLng(47.476325, 19.099294), // Népliget
  LatLng(47.472746, 19.096119),
  LatLng(47.470293, 19.089285),
  LatLng(47.469746, 19.084483),
  LatLng(47.468760, 19.073512), // Közvágóhíd
  LatLng(47.469086, 19.060499), // Rákóczi híd
  LatLng(47.469644, 19.054370), // Infopark
  LatLng(47.467035, 19.049754),
  LatLng(47.462583, 19.048507),
  LatLng(47.462277, 19.043347),
  LatLng(47.463625, 19.033306), // Bikás park
  LatLng(47.464110, 19.029632),
  LatLng(47.464469, 19.023384), // Kelenföld vasútállomás
];

const tram46RoutePoints = <LatLng>[
  LatLng(47.507100, 19.025200), // Széll Kálmán tér
  LatLng(47.509800, 19.032200), // Mechwart liget
  LatLng(47.514000, 19.038500), // Margit híd, budai hídfő
  LatLng(47.515200, 19.047500), // Margitsziget
  LatLng(47.513500, 19.050500), // Jászai Mari tér
  LatLng(47.510900, 19.057000), // Nyugati pályaudvar
  LatLng(47.505023, 19.063233), // Oktogon
  LatLng(47.502000, 19.066500), // Király utca
  LatLng(47.499000, 19.069000), // Wesselényi utca
  LatLng(47.496100, 19.070400), // Blaha Lujza tér
  LatLng(47.492500, 19.071700), // Rákóczi tér
  LatLng(47.489200, 19.071800), // Harminckettesek tere
  LatLng(47.486000, 19.070000), // Corvin-negyed
  LatLng(47.484200, 19.068500), // Mester utca
  LatLng(47.478900, 19.067300), // Boráros tér
  LatLng(47.476000, 19.056000), // Petőfi híd, budai hídfő
  LatLng(47.474000, 19.050000), // Budafoki út
  LatLng(47.473559, 19.046266), // Újbuda-központ / Móricz Zsigmond körtér
  LatLng(47.478000, 19.047500), // Móricz Zsigmond körtér
];

const tram2RoutePoints = <LatLng>[
  LatLng(47.512837, 19.047936), // Jászai Mari tér
  LatLng(47.508879, 19.046582), // Parlament
  LatLng(47.505749, 19.046834), // Kossuth Lajos tér
  LatLng(47.500685, 19.046064), // Széchenyi István tér
  LatLng(47.497969, 19.047020), // Eötvös tér
  LatLng(47.495837, 19.048215), // Vigadó tér
  LatLng(47.490719, 19.051652), // Március 15. tér
  LatLng(47.486941, 19.056482), // Fővám tér
  LatLng(47.483036, 19.062439), // Zsil utca
  LatLng(47.479726, 19.066299), // Boráros tér
  LatLng(47.474022, 19.070622), // Haller utca
  LatLng(47.470972, 19.073181), // Müpa - Nemzeti Színház
  LatLng(47.467527, 19.075886), // Közvágóhíd
];

// --- Railway Mainline Corridors ---

const railwayLine1Points = <LatLng>[
  LatLng(47.500400, 19.083800), // Keleti pu
  LatLng(47.469000, 19.083000), // Ferencváros
  LatLng(47.464600, 19.021500), // Kelenföld
  LatLng(47.452000, 18.966000), // Budaörs
  LatLng(47.468000, 18.825000), // Biatorbágy
  LatLng(47.485000, 18.638000), // Bicske
  LatLng(47.585000, 18.397000), // Tatabánya
  LatLng(47.652000, 18.326000), // Tata
  LatLng(47.746000, 18.125000), // Komárom
  LatLng(47.683000, 17.635000), // Győr
  LatLng(47.868000, 17.274000), // Mosonmagyaróvár
  LatLng(47.915000, 17.155000), // Hegyeshalom
];

const railwayLine30aPoints = <LatLng>[
  LatLng(47.500000, 19.025300), // Déli pu
  LatLng(47.464600, 19.021500), // Kelenföld
  LatLng(47.426000, 19.038000), // Budafok
  LatLng(47.382000, 18.928000), // Érd alsó
  LatLng(47.375000, 18.855000), // Tárnok
  LatLng(47.318000, 18.788000), // Martonvásár
  LatLng(47.198000, 18.625000), // Gárdony
  LatLng(47.185000, 18.428000), // Székesfehérvár
  LatLng(47.042000, 18.245000), // Lepsény
  LatLng(46.908000, 18.055000), // Siófok
];

const railwayLine70Points = <LatLng>[
  LatLng(47.510900, 19.056900), // Nyugati pu
  LatLng(47.531000, 19.086000), // Rákosrendező
  LatLng(47.562000, 19.088000), // Újpest
  LatLng(47.635000, 19.135000), // Dunakeszi
  LatLng(47.695000, 19.142000), // Göd
  LatLng(47.778000, 19.135000), // Vác
  LatLng(47.828000, 19.015000), // Kismaros
  LatLng(47.785000, 18.958000), // Nagymaros-Visegrád
  LatLng(47.798000, 18.908000), // Zebegény
  LatLng(47.818000, 18.868000), // Szob
];

const railwayLine100aPoints = <LatLng>[
  LatLng(47.510900, 19.056900), // Nyugati pu
  LatLng(47.513000, 19.098000), // Zugló
  LatLng(47.487000, 19.128000), // Kőbánya alsó
  LatLng(47.464400, 19.149200), // Kőbánya-Kispest
  LatLng(47.432000, 19.228000), // Ferihegy
  LatLng(47.408000, 19.268000), // Vecsés
  LatLng(47.352000, 19.442000), // Monor
  LatLng(47.178000, 19.795000), // Cegléd
  LatLng(47.168000, 20.180000), // Szolnok
  LatLng(47.318000, 21.112000), // Püspökladány
  LatLng(47.521000, 21.625000), // Debrecen
];

const railwayLine80aPoints = <LatLng>[
  LatLng(47.500400, 19.083800), // Keleti pu
  LatLng(47.492000, 19.128000), // Kőbánya felső
  LatLng(47.498000, 19.172000), // Rákos
  LatLng(47.493000, 19.338000), // Pécel
  LatLng(47.532000, 19.402000), // Isaszeg
  LatLng(47.593000, 19.358000), // Gödöllő
  LatLng(47.658000, 19.488000), // Aszód
  LatLng(47.668000, 19.678000), // Hatvan
  LatLng(47.742000, 20.418000), // Füzesabony
  LatLng(48.102000, 20.805000), // Miskolc-Tiszai
];

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

/// Primary Hungarian railway mainline corridors (MÁV 1, 30a, 70, 80a, 100a, Körvasút).
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
      points: railwayConnectingLinePoints,
      strokeWidth: 2.8,
      color: mavBlue,
      pattern: const StrokePattern.solid(),
    ),
  ];
});
