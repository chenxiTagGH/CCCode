import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/l10n.dart';
import '../../channel/account/account_api.dart';
import '../../models/cc_api_connector.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import 'featured_upstreams_strip.dart';
import 'settings_widgets.dart';

/// The fixed CC API entry point shown before remotely featured providers.
class CcApiCard extends StatefulWidget {
  const CcApiCard({
    super.key,
    required this.connector,
    required this.onChanged,
  });

  final CcApiConnector connector;
  final VoidCallback onChanged;

  @override
  State<CcApiCard> createState() => _CcApiCardState();
}

class _CcApiCardState extends State<CcApiCard> {
  bool _working = false;

  @override
  void didUpdateWidget(covariant CcApiCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connector != oldWidget.connector) _working = false;
  }

  Future<void> _connect() async {
    if (_working) return;
    final connector = widget.connector;
    setState(() => _working = true);
    try {
      await connector.connect(
        chooseKey: (keys) => showCcApiKeyPicker(context, keys),
      );
    } finally {
      if (mounted && identical(widget.connector, connector)) {
        setState(() => _working = false);
        widget.onChanged();
      }
    }
  }

  Future<void> _refresh() async {
    if (_working) return;
    final connector = widget.connector;
    setState(() => _working = true);
    try {
      await connector.refresh(
        chooseKey: (keys) => showCcApiKeyPicker(context, keys),
      );
    } finally {
      if (mounted && identical(widget.connector, connector)) {
        setState(() => _working = false);
        widget.onChanged();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connector = widget.connector;
    final provider = connector.providers.provider(CcApiConnector.providerId);
    final l10n = context.l10n;
    final count = provider?.enabledModels.length ?? 0;
    final status = connector.status == CcApiConnectionStatus.disconnected &&
            provider != null && provider.enabledModels.isNotEmpty
        ? CcApiConnectionStatus.connected
        : connector.status;
    final action = switch (status) {
      CcApiConnectionStatus.disconnected => l10n.modelsCcApiLogin,
      CcApiConnectionStatus.connecting => l10n.modelsCcApiConnecting,
      CcApiConnectionStatus.connected => l10n.modelsCcApiRefresh,
      CcApiConnectionStatus.needsLogin => l10n.modelsCcApiNeedsLogin,
      CcApiConnectionStatus.failed => l10n.modelsCcApiRetry,
    };
    final detail = switch (status) {
      CcApiConnectionStatus.connected => l10n.modelsCcApiConnected(count),
      CcApiConnectionStatus.connecting => l10n.modelsCcApiConnecting,
      CcApiConnectionStatus.needsLogin => l10n.modelsCcApiNeedsLoginDetail,
      CcApiConnectionStatus.failed => l10n.modelsCcApiFailed,
      CcApiConnectionStatus.disconnected => l10n.modelsCcApiDescription,
    };
    final enabled = !_working && status != CcApiConnectionStatus.connecting;
    return SizedBox(
      height: FeaturedUpstreamsStrip.cardHeight,
      width: FeaturedUpstreamsStrip.cardWidth,
      child: Semantics(
        button: true,
        label: '${l10n.modelsCcApiName}, $detail, $action',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? () => unawaited(
                    status == CcApiConnectionStatus.connected
                        ? _refresh()
                        : _connect(),
                  )
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: SettingsColors.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: Center(child: CcCodeLogo(size: 22)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.modelsCcApiName, maxLines: 1, overflow: TextOverflow.ellipsis, style: SettingsText.label.copyWith(fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w500)),
                      Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: SettingsText.description.copyWith(fontSize: 11.5, height: 1.35, color: SettingsColors.textTertiary)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (_working || status == CcApiConnectionStatus.connecting)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: themeColors['textLink.foreground']))
                else ...[
                  Text(action, style: SettingsText.description),
                  const SizedBox(width: 4),
                  Icon(Codicons.chevronRight, size: 14, color: SettingsColors.textSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<AccountKey?> showCcApiKeyPicker(
  BuildContext context,
  List<AccountKey> keys,
) => showDialog<AccountKey>(
  context: context,
  builder: (context) => _CcApiKeyPicker(keys),
);

class _CcApiKeyPicker extends StatefulWidget {
  const _CcApiKeyPicker(this.keys);

  final List<AccountKey> keys;

  @override
  State<_CcApiKeyPicker> createState() => _CcApiKeyPickerState();
}

class _CcApiKeyPickerState extends State<_CcApiKeyPicker> {
  AccountKey? selected;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.modelsCcApiChooseKey),
    content: SizedBox(
      width: 420,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final key in widget.keys)
            RadioListTile<AccountKey>(
              value: key,
              groupValue: selected,
              onChanged: (value) => setState(() => selected = value),
              title: Text(key.name),
              subtitle: Text([
                key.masked,
                if (key.platform case final platform? when platform.isNotEmpty)
                  platform,
              ].join(' · ')),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.commonCancel),
      ),
      FilledButton(
        onPressed: selected == null
            ? null
            : () => Navigator.of(context).pop(selected),
        child: Text(context.l10n.modelsCcApiChoose),
      ),
    ],
  );
}

class CcCodeLogo extends StatelessWidget {
  const CcCodeLogo({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/branding/cccode_logo.svg',
        width: size,
        height: size,
      );
}
