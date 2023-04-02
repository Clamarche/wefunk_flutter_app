import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

class WefunkTimeStampDetails {
  late int timeStamp; // The time stamp of the track
  late String songIndex; // The index of the track

  WefunkTimeStampDetails(this.timeStamp, this.songIndex);
}

class WefunkSongDetails {
  late String title; // The title of the song
  late String artist; // The artist of the song

  WefunkSongDetails(this.title, this.artist);
}

class WefunkShowDetails {
  late int showNumber; // The number of the show
  late int duration; // The duration of the show
  late DateTime showDate; // The date of the show

  WefunkShowDetails(this.showNumber, this.duration, this.showDate);
}

class WefunkSong {
  late String title; // The title of the song
  late String artist; // The artist of the song
  late int timeStamp; // The time stamp of the song
  late int duration; // The duration of the song

  WefunkSong(this.title, this.artist, this.timeStamp, this.duration);
}

class WefunkShow {
  late int showNumber; // The number of the show
  String baseUrl = "https://www.wefunkradio.com";
  String streamRelPath = "mirror/stream";

  WefunkShow(this.showNumber);

  String getStreamUrl() {
    return "$baseUrl/$streamRelPath/${showNumber.toString()}"; // https://www.wefunkradio.com/mirror/stream/1151
  }

  String getShowUrl() {
    return "$baseUrl/show/${showNumber.toString()}";
  }

  dynamic _getShowTracksJson(String htmlBody) {
    // Extract the timestamp infor about the tracks json object
    final regexTrackTimeStamp = RegExp(r'var tracks = ({.*})(?=;)');
    RegExpMatch? matchTrackTimeStamp = regexTrackTimeStamp.firstMatch(htmlBody);

    if (matchTrackTimeStamp == null) {
      return {};
    } else {
      String trackTimeStampString =
          matchTrackTimeStamp[0]?.replaceAll("var tracks = ", "") as String;

      return jsonDecode(trackTimeStampString);
    }
  }

  List<WefunkTimeStampDetails> _getTrackTimeStamp(String htmlBody) {
    // Extract the timestamp infor about the tracks json object
    final dynamic jsonTrackTimeStamp = _getShowTracksJson(htmlBody);

    if (jsonTrackTimeStamp.containsKey('tracks')) {
      List<WefunkTimeStampDetails> tracksTimeStamp = [];
      for (var track in jsonTrackTimeStamp['tracks']) {
        tracksTimeStamp.add(WefunkTimeStampDetails(
          track['mspos'],
          track['ix'],
        ));
      }
      return tracksTimeStamp;
    } else {
      return [];
    }
  }

  WefunkShowDetails? getShowDetails(String htmlBody) {
    // Extract the timestamp infor about the tracks json object
    final dynamic jsonShowDetails = _getShowTracksJson(htmlBody);

    if (jsonShowDetails.containsKey('tracks')) {
      return WefunkShowDetails(
          int.parse(jsonShowDetails['shownum']),
          jsonShowDetails['mstotal'],
          DateTime.parse(jsonShowDetails['showdate']));
    } else {
      return null;
    }
  }

  List<WefunkSongDetails> _getTrackDetails(String htmlBody) {
    // Extract the track details json object
    final regexTrackDetail = RegExp(r'var trackextra = (\[.*\])(?=;)');
    RegExpMatch? matchTrackDetail = regexTrackDetail.firstMatch(htmlBody);
    // print(matchTrackDetail?[0]);

    if (matchTrackDetail == null) {
      return [];
    } else {
      String trackDetailString =
          matchTrackDetail[0]?.replaceAll("var trackextra = ", "") as String;

      dynamic jsonTrackDetail = jsonDecode(trackDetailString);
      List<WefunkSongDetails> tracksDetail = [];
      for (var track in jsonTrackDetail) {
        if (track.isEmpty) {
          tracksDetail
              .add(WefunkSongDetails("Intro", 'DJ Static & Professor Groove'));
        } else {
          tracksDetail.add(WefunkSongDetails(track[0]['t'], track[0]['a']));
        }
      }
      return tracksDetail;
    }
  }

  String nextIndex(String previousIndex) {
    int charA = 'a'.codeUnitAt(0);
    int charZ = 'z'.codeUnitAt(0);

    int firstChar = previousIndex.substring(0, 1).codeUnitAt(0);
    int secondChar = previousIndex.substring(1, 2).codeUnitAt(0);

    // Check if the index is valid
    if (firstChar < charA ||
        firstChar > charZ ||
        secondChar < charA ||
        secondChar > charZ) {
      throw Exception(
          "Invalid index ($previousIndex) : Each char must be between a and z");
    }

    if (firstChar == charZ && secondChar == charZ) {
      return 'zz'; // End of the Index
    }

    if (secondChar == charZ) {
      return "${String.fromCharCode(firstChar + 1)}a";
    } else {
      return "${String.fromCharCode(firstChar)}${String.fromCharCode(secondChar + 1)}";
    }
  }

  List<WefunkSong> _mergeTrackInfo(List<WefunkSongDetails> tracksDetail,
      List<WefunkTimeStampDetails> tracksTimeStamp, int showDuration) {
    // Note: Intro has no info in TrackDetails (empty list)

    // Merge the two map
    List<WefunkSong> tracksInfo = [];

    if (tracksTimeStamp.isNotEmpty) {
      for (int i = 0; i < tracksTimeStamp.length; i++) {
        WefunkTimeStampDetails trackTimeStamp = tracksTimeStamp[i];
        WefunkSongDetails trackDetail = tracksDetail[i];

        int duration = i < tracksTimeStamp.length - 1
            ? tracksTimeStamp[i + 1].timeStamp - trackTimeStamp.timeStamp
            : showDuration - trackTimeStamp.timeStamp;

        tracksInfo.add(WefunkSong(
          trackDetail.title,
          trackDetail.artist,
          trackTimeStamp.timeStamp,
          duration,
        ));
      }

      return tracksInfo;
    }

    return [];
  }

  // Get the tracks info from the show html
  //
  // Extract a Map containing the information about the tracks timestamps on
  // the stream.
  Future<List<WefunkSong>> getTracksInfo() async {
    // Download the show
    final httpClient = HttpClient();
    final request = await httpClient.getUrl(Uri.parse(getShowUrl()));
    final response = await request.close();
    // Get the response body
    final responseBody = await response.transform(utf8.decoder).join();

    // Extract the track details json object
    final trackDetails = _getTrackDetails(responseBody);
    final trackTimeStamps = _getTrackTimeStamp(responseBody);
    final showDetails = getShowDetails(responseBody);

    return _mergeTrackInfo(
        trackDetails, trackTimeStamps, showDetails?.duration ?? 0);
  }

  Future downloadShow() async {
    // Download the show
    final httpClient = HttpClient();
    final request = await httpClient.getUrl(Uri.parse(getShowUrl()));
    final response = await request.close();
    final filePath = path.join("download", "show${showNumber.toString()}.html");

    // Write the response to a file
    response.pipe(File(filePath).openWrite());
    httpClient.close();
  }

  Future downloadStream() async {
    // Download the stream
    final httpClient = HttpClient();
    final request = await httpClient.getUrl(Uri.parse(getStreamUrl()));
    final response = await request.close();
    final filePath =
        path.join("download", "stream${showNumber.toString()}.mp3");

    // Write the response to a file
    response.pipe(File(filePath).openWrite());
    httpClient.close();
  }
}
