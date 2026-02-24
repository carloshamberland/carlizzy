import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/ai_providers/ai_provider.dart';
import '../../../../core/ai_providers/ai_provider_manager.dart';
import '../../../../core/services/credits_service.dart';
import '../../../../core/services/recent_photos_service.dart';
import '../../domain/entities/garment.dart';
import '../../domain/entities/tryon_result.dart';
import '../../domain/entities/user_image.dart';
import '../../domain/usecases/select_user_image.dart';
import 'tryon_event.dart';
import 'tryon_state.dart';

class TryonBloc extends Bloc<TryonEvent, TryonState> {
  final SelectUserImage selectUserImage;
  final AIProviderManager providerManager;
  final CreditsService creditsService;
  final ImagePicker _imagePicker;

  // Current session state
  UserImage? _personImage;
  bool _isPersonUrl = false;
  /// Map of category -> clothing selection (supports multiple items)
  Map<String, ClothingSelection> _clothingItems = {};

  TryonBloc({
    required this.selectUserImage,
    required this.providerManager,
    required this.creditsService,
    required ImagePicker imagePicker,
  })  : _imagePicker = imagePicker,
        super(TryonInitial(
          selectedProvider: providerManager.currentType,
          availableProviders: providerManager.availableProviders,
          credits: creditsService.getCredits(),
        )) {
    on<SelectPersonPhotoEvent>(_onSelectPersonPhoto);
    on<SetPersonImageUrlEvent>(_onSetPersonImageUrl);
    on<SetPersonImagePathEvent>(_onSetPersonImagePath);
    on<SelectClothingImageEvent>(_onSelectClothingImage);
    on<SetClothingUrlEvent>(_onSetClothingUrl);
    on<SetClothingPathEvent>(_onSetClothingPath);
    on<ChangeProviderEvent>(_onChangeProvider);
    on<StartTryOnEvent>(_onStartTryOn);
    on<RetryTryOnEvent>(_onRetryTryOn);
    on<ResetTryonEvent>(_onResetTryon);
    on<ClearClothingEvent>(_onClearClothing);
    on<UseResultAsBaseEvent>(_onUseResultAsBase);
  }

  Future<void> _onSelectPersonPhoto(
    SelectPersonPhotoEvent event,
    Emitter<TryonState> emit,
  ) async {
    final result = await selectUserImage(event.source);

    result.fold(
      (failure) => emit(TryonErrorState(
        message: failure.message,
        canRetry: true,
      )),
      (userImage) {
        _personImage = userImage;
        _isPersonUrl = false;
        // Save to recent photos
        RecentPhotosService.addPhoto(userImage.path);
        _emitCurrentState(emit);
      },
    );
  }

  void _onSetPersonImageUrl(
    SetPersonImageUrlEvent event,
    Emitter<TryonState> emit,
  ) {
    // Create a UserImage with the URL as path for demo purposes
    _personImage = UserImage(
      path: event.url,
      fileName: 'sample_person.jpg',
      size: 0,
      aspectRatio: 1.0,
    );
    _isPersonUrl = true;
    _emitCurrentState(emit);
  }

  void _onSetPersonImagePath(
    SetPersonImagePathEvent event,
    Emitter<TryonState> emit,
  ) {
    // Create a UserImage from file path (for recent photos)
    _personImage = UserImage(
      path: event.path,
      fileName: event.path.split('/').last,
      size: 0,
      aspectRatio: 1.0,
    );
    _isPersonUrl = false;
    // Save to recent photos
    RecentPhotosService.addPhoto(event.path);
    _emitCurrentState(emit);
  }

  Future<void> _onSelectClothingImage(
    SelectClothingImageEvent event,
    Emitter<TryonState> emit,
  ) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: event.source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        // Handle dress vs top/bottom conflicts
        _handleClothingConflicts(event.category);

        _clothingItems[event.category] = ClothingSelection(
          imagePath: pickedFile.path,
          isUrl: false,
        );
        _emitCurrentState(emit);
      }
    } catch (e) {
      emit(TryonErrorState(
        message: 'Failed to select clothing image: $e',
        canRetry: true,
      ));
    }
  }

  void _onSetClothingUrl(
    SetClothingUrlEvent event,
    Emitter<TryonState> emit,
  ) {
    // Handle dress vs top/bottom conflicts
    _handleClothingConflicts(event.category);

    _clothingItems[event.category] = ClothingSelection(
      imagePath: event.url,
      isUrl: true,
    );
    _emitCurrentState(emit);
  }

  void _onSetClothingPath(
    SetClothingPathEvent event,
    Emitter<TryonState> emit,
  ) {
    // Handle dress vs top/bottom conflicts
    _handleClothingConflicts(event.category);

    _clothingItems[event.category] = ClothingSelection(
      imagePath: event.path,
      isUrl: false,
    );
    _emitCurrentState(emit);
  }

  /// Handle conflicts between dress and top/bottom selections
  /// - Selecting a dress clears any top or bottom
  /// - Selecting a top or bottom clears any dress
  void _handleClothingConflicts(String category) {
    if (category == 'full_body') {
      // Selecting dress: clear top and bottom
      _clothingItems.remove('upper_body');
      _clothingItems.remove('lower_body');
    } else if (category == 'upper_body' || category == 'lower_body') {
      // Selecting top or bottom: clear dress
      _clothingItems.remove('full_body');
    }
  }

  Future<void> _onChangeProvider(
    ChangeProviderEvent event,
    Emitter<TryonState> emit,
  ) async {
    // Only FitRoom is available, no provider switching needed
    _emitCurrentState(emit);
  }

  Future<void> _onStartTryOn(
    StartTryOnEvent event,
    Emitter<TryonState> emit,
  ) async {
    if (_personImage == null || _clothingItems.isEmpty) {
      emit(const TryonErrorState(
        message: 'Please select both a photo and at least one clothing item',
        canRetry: false,
      ));
      return;
    }

    final provider = providerManager.currentProvider;
    final totalSteps = _clothingItems.length;
    final categories = _clothingItems.keys.toList();

    // Check if user has enough credits
    final creditsNeeded = creditsService.creditsNeeded(totalSteps);
    if (!creditsService.hasEnoughCredits(totalSteps)) {
      emit(TryonErrorState(
        message: 'Not enough credits. You need $creditsNeeded credits but have ${creditsService.getCredits()}.',
        canRetry: false,
      ));
      return;
    }

    // Sort categories for consistent order: tops -> bottoms -> dresses -> shoes -> accessories
    final categoryOrder = ['upper_body', 'lower_body', 'full_body', 'shoes', 'accessories'];
    categories.sort((a, b) {
      final aIndex = categoryOrder.indexOf(a);
      final bIndex = categoryOrder.indexOf(b);
      return aIndex.compareTo(bIndex);
    });

    emit(ProcessingTryOnState(
      personImage: _personImage!,
      clothingItems: Map.from(_clothingItems),
      progress: 0.0,
      statusMessage: 'Starting ${provider.type.displayName}...',
      provider: provider.type,
      currentStep: 1,
      totalSteps: totalSteps,
      currentCategory: categories.first,
    ));

    try {
      // Start with person image
      File currentPersonFile;
      if (_isPersonUrl) {
        emit(ProcessingTryOnState(
          personImage: _personImage!,
          clothingItems: Map.from(_clothingItems),
          progress: 0.02,
          statusMessage: 'Downloading person image...',
          provider: provider.type,
          currentStep: 1,
          totalSteps: totalSteps,
          currentCategory: categories.first,
        ));
        currentPersonFile = await _downloadImage(_personImage!.path);
      } else {
        currentPersonFile = File(_personImage!.path);
      }

      String? lastResultUrl;

      // Process each clothing item in sequence
      for (int i = 0; i < categories.length; i++) {
        final category = categories[i];
        final clothing = _clothingItems[category]!;
        final stepNum = i + 1;
        final categoryName = _getCategoryDisplayName(category);

        emit(ProcessingTryOnState(
          personImage: _personImage!,
          clothingItems: Map.from(_clothingItems),
          progress: 0.0,
          statusMessage: 'Adding $categoryName ($stepNum of $totalSteps)...',
          provider: provider.type,
          currentStep: stepNum,
          totalSteps: totalSteps,
          currentCategory: category,
        ));

        final result = await provider.tryOn(
          personImage: currentPersonFile,
          garmentImage: clothing.imagePath,
          category: category,
          onProgress: (progress, status) {
            emit(ProcessingTryOnState(
              personImage: _personImage!,
              clothingItems: Map.from(_clothingItems),
              progress: progress,
              statusMessage: '$categoryName: $status',
              provider: provider.type,
              currentStep: stepNum,
              totalSteps: totalSteps,
              currentCategory: category,
            ));
          },
        );

        // Deduct credits for this article (10 credits per article)
        await creditsService.deductCredits(1);

        lastResultUrl = result.resultImageUrl;

        // If there are more items, download the result to use as the next person image
        if (i < categories.length - 1) {
          emit(ProcessingTryOnState(
            personImage: _personImage!,
            clothingItems: Map.from(_clothingItems),
            progress: 0.95,
            statusMessage: 'Preparing for next item...',
            provider: provider.type,
            currentStep: stepNum,
            totalSteps: totalSteps,
            currentCategory: category,
          ));
          currentPersonFile = await _downloadImage(result.resultImageUrl);
        }
      }

      emit(TryonSuccessState(
        result: TryonResult(
          resultImageUrl: lastResultUrl!,
          originalImage: _personImage!,
          garment: Garment(
            imageUrl: _clothingItems.values.first.imagePath,
            description: 'Outfit with ${_clothingItems.length} items',
            category: categories.first,
            timestamp: DateTime.now(),
          ),
          createdAt: DateTime.now(),
        ),
        personImage: _personImage!,
        clothingItems: Map.from(_clothingItems),
        usedProvider: provider.type,
        itemsProcessed: totalSteps,
      ));
    } catch (e) {
      emit(TryonErrorState(
        message: e.toString(),
        canRetry: true,
        lastProvider: provider.type,
      ));
    }
  }

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'upper_body':
        return 'top';
      case 'lower_body':
        return 'bottom';
      case 'full_body':
        return 'dress';
      case 'shoes':
        return 'shoes';
      case 'accessories':
        return 'accessory';
      default:
        return category;
    }
  }

  Future<void> _onRetryTryOn(
    RetryTryOnEvent event,
    Emitter<TryonState> emit,
  ) async {
    add(const StartTryOnEvent());
  }

  void _onResetTryon(
    ResetTryonEvent event,
    Emitter<TryonState> emit,
  ) {
    _personImage = null;
    _isPersonUrl = false;
    _clothingItems = {};
    emit(TryonInitial(
      selectedProvider: providerManager.currentType,
      availableProviders: providerManager.availableProviders,
      credits: creditsService.getCredits(),
    ));
  }

  void _onClearClothing(
    ClearClothingEvent event,
    Emitter<TryonState> emit,
  ) {
    if (event.category != null) {
      // Clear specific category
      _clothingItems.remove(event.category);
    } else {
      // Clear all clothing
      _clothingItems = {};
    }
    _emitCurrentState(emit);
  }

  Future<void> _onUseResultAsBase(
    UseResultAsBaseEvent event,
    Emitter<TryonState> emit,
  ) async {
    try {
      // Download the result image to use as new base
      final downloadedFile = await _downloadImage(event.resultImageUrl);

      // Set it as the new person image
      _personImage = UserImage(
        path: downloadedFile.path,
        fileName: downloadedFile.path.split('/').last,
        size: 0,
        aspectRatio: 1.0,
      );
      _isPersonUrl = false;

      // Clear all clothing selections
      _clothingItems = {};

      // Emit the person selected state so user can choose new articles
      _emitCurrentState(emit);
    } catch (e) {
      emit(TryonErrorState(
        message: 'Failed to use result as base: $e',
        canRetry: true,
      ));
    }
  }

  void _emitCurrentState(Emitter<TryonState> emit) {
    final credits = creditsService.getCredits();
    if (_personImage == null) {
      // No person selected - show initial state with any selected clothing
      emit(TryonInitial(
        selectedProvider: providerManager.currentType,
        availableProviders: providerManager.availableProviders,
        credits: credits,
        clothingItems: Map.from(_clothingItems),
      ));
    } else if (_clothingItems.isEmpty) {
      emit(PersonSelectedState(
        personImage: _personImage!,
        isPersonUrl: _isPersonUrl,
        selectedProvider: providerManager.currentType,
        availableProviders: providerManager.availableProviders,
        credits: credits,
      ));
    } else {
      emit(TryonReadyState(
        personImage: _personImage!,
        isPersonUrl: _isPersonUrl,
        clothingItems: Map.from(_clothingItems),
        selectedProvider: providerManager.currentType,
        availableProviders: providerManager.availableProviders,
        credits: credits,
      ));
    }
  }

  Future<File> _downloadImage(String url) async {
    final dio = Dio();
    final tempDir = await getTemporaryDirectory();
    final fileName = 'person_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = '${tempDir.path}/$fileName';

    await dio.download(url, filePath);
    return File(filePath);
  }
}
