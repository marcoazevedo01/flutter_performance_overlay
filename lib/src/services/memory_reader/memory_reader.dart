export 'memory_reader_stub.dart'
    if (dart.library.io) 'memory_reader_io.dart'
    if (dart.library.js_interop) 'memory_reader_web.dart';
