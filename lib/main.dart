import "dart:async" show StreamSubscription;
import "dart:convert" show jsonDecode;
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_compass/flutter_compass.dart";
import "package:location/location.dart";
import "package:vector_math/vector_math.dart" show Vector2, degrees, radians;
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
        body: Center(child: SingleChildScrollView(child: LocationFinder())),
      ),
    );
  }
}

class LocationFinder extends StatefulWidget {
  const LocationFinder({super.key});

  @override
  State<LocationFinder> createState() => _LocationFinderState();
}

const placeTypeFilterDict = {
  "Any": "[name]",
  "Attraction": "[wikidata]",
  "Restaurant": "[amenity=restaurant]",
  "Fast Food": "[amenity=fast_food]",
  "Cafe": "[amenity=cafe]",
  "Hotel": "[tourism=hotel]",
  "Shop": "[shop]",
};

class _LocationFinderState extends State<LocationFinder> {
  Future<Vector2?>? _placeFuture;
  final _rangeField = TextEditingController(text: "1000");
  String _placeType = "Any";
  Vector2 _currentLocation = Vector2.zero();
  StreamSubscription<LocationData>? _locationStream;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _placeFuture,
        builder: (context, snapshot) {
          return Column(
            children: [
              Container(
                  margin: const EdgeInsets.only(bottom: 32.0),
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
              withLabel(
                "Range: ",
                "m",
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    controller: _rangeField,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly
                    ],
                  ),
                ),
              ),
              withLabel(
                  "Type: ",
                  "",
                  DropdownButton(
                    value: _placeType,
                    style: biggerFont,
                    items: placeTypeFilterDict.keys.map((value) {
                      return DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _placeType = v!),
                  )),
              Container(
                margin: const EdgeInsets.only(top: 32),
                child: ElevatedButton(
                    onPressed:
                        snapshot.connectionState == ConnectionState.waiting
                            ? null
                            : _onFindButtonPress,
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("Find Place", style: largeFont),
                    )),
              ),
            ],
          );
        });
  }

  void _onFindButtonPress() {
    if (_placeFuture == null) {
      return _setFuture();
    }

    final dialog = AlertDialog(
      title: const Text("Are you sure want to find a new place?"),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _setFuture();
            },
            child: const Text("Yes")),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel")),
      ],
    );

    showDialog(context: context, builder: (context) => dialog);
  }

  void _setFuture() {
    setState(() {
      _placeFuture = _fetchPlace();
    });
  }

  Widget _buildCompass(AsyncSnapshot<Vector2?> snapshot) {
    String? error;

    if (snapshot.connectionState == ConnectionState.none) {
      return const Text("TokoThere",
          style: TextStyle(fontSize: 36), textAlign: TextAlign.center);
    } else if (snapshot.connectionState == ConnectionState.waiting) {
      return const CircularProgressIndicator();
    } else if (snapshot.hasError) {
      if (snapshot.error is PlatformException) {
        final exception = snapshot.error as PlatformException;
        error = exception.message!;
      } else {
        error = snapshot.error.toString();
      }
    } else if (snapshot.data == null) {
      error = "No place found within area";
    }

    if (error != null) {
      _placeFuture = null;
      return Text(error, style: biggerFont, textAlign: TextAlign.center);
    } else {
      return Compass(
        target: snapshot.data!,
        current: _currentLocation,
      );
    }
  }

  Future<LocationData> _getLocation() {
    _locationStream ??= Location.instance.onLocationChanged.listen((location) {
      _currentLocation = Vector2(location.longitude!, location.latitude!);
    });

    return Location.instance.getLocation();
  }

  Future<Vector2?> _fetchPlace() async {
    final location = await _getLocation();
    final lat = location.latitude;
    final lon = location.longitude;
    final dist = int.parse(_rangeField.text);
    final tagFilter = placeTypeFilterDict[_placeType];
    final response = await http.get(Uri.parse(
        "https://overpass-api.de/api/interpreter?data=[out:json][timeout:20];node(around:${dist * 1.1},$lat,$lon)$tagFilter->.a;node(around:${dist * 0.8},$lat,$lon)$tagFilter->.b;(.a; - .b;);out skel noids;"));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final elements = data["elements"] as List;
      if (elements.isNotEmpty) {
        final index = random.nextInt(data["elements"].length);
        final node = data["elements"][index];
        return Vector2(node["lon"], node["lat"]);
      } else {
        return null;
      }
    } else {
      throw "Failed to fetch https://overpass-api.de ${response.statusCode}";
    }
  }
}

class Compass extends StatefulWidget {
  const Compass({
    super.key,
    required this.target,
    required this.current,
  });

  final Vector2 target;
  final Vector2 current;

  @override
  State<Compass> createState() => _CompassState();
}

class _CompassState extends State<Compass> {
  double _prevHeading = 0.0;
  double _turns = 0.0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text("Error reading heading: ${snapshot.error}");
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

        final diffCoords = widget.target - widget.current;
        final targetDir = math.atan2(diffCoords.y, diffCoords.x);
        final heading = degrees(targetDir) - northDir + 90;

        // Make sure arrow doesn't flip to other side
        double diff = heading - _prevHeading;
        if (diff.abs() > 180) {
          if (_prevHeading > heading) {
            diff = 360 - (heading - _prevHeading).abs();
          } else {
            diff = (360 - (_prevHeading - heading).abs()) * -1.0;
          }
        }
        _turns += (diff / 360);
        _prevHeading = heading;

        // Uses https://en.wikipedia.org/wiki/Haversine_formula
        final sinDLat = math.sin(radians(diffCoords.y / 2));
        final sinDLon = math.sin(radians(diffCoords.x / 2));
        final cosLat = math.cos(radians(widget.current.y)) *
            math.cos(radians(widget.target.y));
        final a = math.pow(sinDLat, 2) + cosLat * math.pow(sinDLon, 2);
        final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
        const earthR = 6378.137;
        final dist = (earthR * c * 1000).round();

        return Column(children: [
          AnimatedRotation(
              turns: _turns,
              duration: const Duration(milliseconds: 500),
              curve: Curves.ease,
              child: const Icon(Icons.arrow_right_alt,
                  size: 275, color: Colors.white)),
          Transform.translate(
            offset: const Offset(0, -15),
            child: Text("${dist}m", style: largeFont),
          ),
        ]);
      },
    );
  }
}

Widget withLabel(String label, String endLabel, Widget widget) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(label, style: biggerFont),
      widget,
      Text(endLabel, style: biggerFont)
    ],
  );
}
