import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Custom picker builder delegate that overrides the viewer/preview navigation
/// to skip the picker's built-in viewer and directly return the selected assets.
/// This allows the chat screen to navigate straight to MediaPreviewScreen (send screen).
class CustomAssetPickerBuilderDelegate
    extends DefaultAssetPickerBuilderDelegate {
  CustomAssetPickerBuilderDelegate({
    required super.provider,
    required super.initialPermission,
    super.gridCount,
    super.pickerTheme,
    super.specialItemPosition,
    super.specialItemBuilder,
    super.loadingIndicatorBuilder,
    super.selectPredicate,
    super.shouldRevertGrid,
    super.limitedPermissionOverlayPredicate,
    super.pathNameBuilder,
    super.assetsChangeCallback,
    super.assetsChangeRefreshPredicate,
    super.themeColor,
    super.textDelegate,
    super.locale,
    super.gridThumbnailSize,
    super.previewThumbnailSize,
    super.specialPickerType,
    super.keepScrollOffset,
    super.shouldAutoplayPreview,
  });

  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    AssetEntity currentAsset,
  ) async {
    final p = context.read<DefaultAssetPickerProvider>();

    // Get the selected assets — if none selected, use the tapped asset
    final List<AssetEntity> assetsToSend = p.selectedAssets.isNotEmpty
        ? List<AssetEntity>.from(p.selectedAssets)
        : [currentAsset];

    if (assetsToSend.isEmpty) return;

    // Pop the picker directly with the selected assets.
    // The chat screen will navigate to MediaPreviewScreen (send screen).
    if (context.mounted) {
      Navigator.maybeOf(context)?.maybePop(assetsToSend);
    }
  }
}
