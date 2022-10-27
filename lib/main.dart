import "dart:async" show StreamSubscription;
import "dart:convert" show jsonDecode;
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_compass/flutter_compass.dart";
import "package:location/location.dart";
import "package:vector_math/vector_math.dart" show Vector2, radians;
import "package:http/http.dart" as http;

const largeFont = TextStyle(fontSize: 24);
const biggerFont = TextStyle(fontSize: 18);
final random = math.Random();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "TokoThere",
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(
        body: LocationFinder(),
      ),
    );
  }
}

class LocationFinder extends StatefulWidget {
  const LocationFinder({super.key});

  @override
  State<LocationFinder> createState() => _LocationFinderState();
}

class _LocationFinderState extends State<LocationFinder> {
  final List<Vector2> _locationCache = [];
  Future<Vector2?>? _locationFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _locationFuture,
        builder: (context, snapshot) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  margin: const EdgeInsets.symmetric(vertical: 64.0),
                  alignment: Alignment.center,
                  child: Material(
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      color: Colors.black26,
                      elevation: 4.0,
                      child: Container(
                          alignment: Alignment.center,
                          width: 325,
                          height: 325,
                          child: _buildCompass(snapshot)))),
              ElevatedButton(
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : () =>
                          setState(() => {_locationFuture = _fetchLocation()}),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("Locate Place", style: largeFont),
                  )),
            ],
          );
        });
  }

  Widget _buildCompass(AsyncSnapshot<Vector2?> snapshot) {
    String? text;

    if (snapshot.connectionState == ConnectionState.none) {
      text = "Press button";
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      return const CircularProgressIndicator();
    } else if (snapshot.hasError) {
      if (snapshot.error is PlatformException) {
        final exception = snapshot.error as PlatformException;
        text = exception.message!;
      } else {
        text = snapshot.error.toString();
      }
    } else if (snapshot.data == null) {
      text = "No location found nearby";
    }

    if (text != null) {
      return Text(text, style: biggerFont, textAlign: TextAlign.center);
    } else {
      return Compass(
        target: snapshot.data!,
      );
    }
  }

  // Uses this query:
  // [out:json][timeout:20];
  // (
  //   node(around:$DISTANCE,$LAT,$LON)[name];
  // );
  // out skel noids;
  Future<Vector2?> _fetchLocation() async {
    if (_locationCache.isNotEmpty) {
      return _chooseRandomCache();
    }

    final current = await Location.instance.getLocation();
    const distance = 1000;
    final response = await http.get(Uri.parse(
        "https://overpass-api.de/api/interpreter?data=%5Bout%3Ajson%5D%5Btimeout%3A20%5D%3B%28node%28around%3A$distance%2C${current.latitude}%2C${current.longitude}%29%5Bname%5D%3B%29%3Bout%20skel%20noids%3B"));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      for (final node in data["elements"]) {
        _locationCache.add(Vector2(node["lon"], node["lat"]));
      }

      return _chooseRandomCache();
    } else {
      throw "Failed to fetch https://overpass-api.de";
    }
  }

  Vector2? _chooseRandomCache() {
    if (_locationCache.isEmpty) return null;
    final index = random.nextInt(_locationCache.length);
    return _locationCache.removeAt(index);
  }
}

class Compass extends StatefulWidget {
  const Compass({
    super.key,
    required this.target,
  });

  final Vector2 target;

  @override
  State<Compass> createState() => _CompassState();
}

class _CompassState extends State<Compass> {
  Vector2? _current;
  double _prevHeading = 0.0;
  double _turns = 0.0;

  @override
  void initState() {
    Location.instance.onLocationChanged.listen((LocationData location) {
      _current = Vector2(location.longitude!, location.latitude!);
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Error reading heading: ${snapshot.error}');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        double? northDir = snapshot.data!.heading;
        if (northDir == null) {
          return const Center(
            child: Text("Device does not have sensors!"),
          );
        }

        northDir += 180;
        // print(northDir);
        final diffCoords = widget.target - Vector2.zero();
        final targetDir = math.atan2(diffCoords.y, diffCoords.x);
        final heading = targetDir - northDir;

        final diff = _prevHeading - heading;
        _turns += diff;
        _prevHeading = heading;

        final diffKM = Vector2(
            40075 * diffCoords.x * math.cos(diffCoords.y) / 360,
            diffCoords.y * 111.32);

        return Column(children: [
          AnimatedRotation(
              turns: _turns,
              duration: const Duration(milliseconds: 500),
              curve: Curves.ease,
              // angle: targetDir - northDir - math.pi / 2,
              child: const Icon(Icons.arrow_right_alt,
                  size: 275, color: Colors.white)),
          Transform.translate(
            offset: const Offset(0, -15),
            child: Text("${(diffKM.length * 1000).round()}m", style: largeFont),
          ),
        ]);
      },
    );
  }
}
