import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/ai_providers/ai_provider.dart';

abstract class TryonEvent extends Equatable {
  const TryonEvent();

  @override
  List<Object?> get props => [];
}

/// Select the user's photo (person to try clothes on)
class SelectPersonPhotoEvent extends TryonEvent {
  final ImageSource source;

  const SelectPersonPhotoEvent(this.source);

  @override
  List<Object?> get props => [source];
}

/// Select a clothing image from gallery or camera
class SelectClothingImageEvent extends TryonEvent {
  final ImageSource source;
  final String category;

  const SelectClothingImageEvent(this.source, {required this.category});

  @override
  List<Object?> get props => [source, category];
}

/// Set clothing image from URL (internet example)
class SetClothingUrlEvent extends TryonEvent {
  final String url;
  final String category;

  const SetClothingUrlEvent(this.url, {required this.category});

  @override
  List<Object?> get props => [url, category];
}

/// Set clothing image from file path (camera/gallery)
class SetClothingPathEvent extends TryonEvent {
  final String path;
  final String category;

  const SetClothingPathEvent(this.path, {required this.category});

  @override
  List<Object?> get props => [path, category];
}

/// Set person image from URL (sample image)
class SetPersonImageUrlEvent extends TryonEvent {
  final String url;

  const SetPersonImageUrlEvent(this.url);

  @override
  List<Object?> get props => [url];
}

/// Set person image from file path (recent photos)
class SetPersonImagePathEvent extends TryonEvent {
  final String path;

  const SetPersonImagePathEvent(this.path);

  @override
  List<Object?> get props => [path];
}

/// Change the AI provider
class ChangeProviderEvent extends TryonEvent {
  final AIProviderType provider;

  const ChangeProviderEvent(this.provider);

  @override
  List<Object?> get props => [provider];
}

/// Start the try-on process
class StartTryOnEvent extends TryonEvent {
  const StartTryOnEvent();
}

/// Retry the last try-on attempt
class RetryTryOnEvent extends TryonEvent {
  const RetryTryOnEvent();
}

/// Reset everything back to initial state
class ResetTryonEvent extends TryonEvent {
  const ResetTryonEvent();
}

/// Clear clothing selection for a specific category (or all if null)
class ClearClothingEvent extends TryonEvent {
  final String? category;

  const ClearClothingEvent({this.category});

  @override
  List<Object?> get props => [category];
}

/// Use the current result image as the new base photo for adding more articles
class UseResultAsBaseEvent extends TryonEvent {
  final String resultImageUrl;

  const UseResultAsBaseEvent(this.resultImageUrl);

  @override
  List<Object?> get props => [resultImageUrl];
}
