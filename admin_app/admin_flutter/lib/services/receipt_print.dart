export 'receipt_print_stub.dart'
    if (dart.library.html) 'receipt_print_web.dart'
    if (dart.library.io) 'receipt_print_io.dart';
