import 'dart:async';
import "dart:io" show Platform;
import "package:grinder/grinder.dart";

void main(args) => grind(args);

final pubCommand = Platform.isWindows ? "pub.bat" : "pub";

@Task("Runs the Dart analyzer on bin/server.dart and web/main.dart.")
void analyze() {
  Analyzer.analyze(const ["bin/server.dart", "web/main.dart"]);
}

@Task("Serve")
@Depends(analyze)
Future serve() {
  var pubServe = runAsync(pubCommand, arguments: const ["serve", "--port", "8000"]);
  var server = runAsync("dart", arguments: const ["bin/server.dart"]);
  // TODO: Run `watch` command on dson transformers

  return Future.wait([pubServe, server], eagerError: true);
}

// Alias serve to run
@Task("run")
run() => serve();

@DefaultTask("Build")
@Depends(analyze)
void build() {
  Pub.build();
}

@Task("Deploys the application to the target server via SSH and Docker.")
void deploy() {
  throw new UnimplementedError();
}
