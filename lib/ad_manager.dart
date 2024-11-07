// ad_manager.dart

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;

class AdManager {
  static final AdManager _instance = AdManager._internal();
  factory AdManager() => _instance;
  AdManager._internal();

  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // 테스트 광고 ID
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    throw UnsupportedError('지원하지 않는 플랫폼입니다');
  }

  BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          print('배너 광고가 로드되었습니다.');
          _bannerAd = ad as BannerAd;
          _isAdLoaded = true;
        },
        onAdFailedToLoad: (ad, error) {
          print('배너 광고 로드 실패: $error');
          ad.dispose();
          _isAdLoaded = false;
        },
      ),
    );
  }

  Widget? getBannerAdWidget() {
    if (_bannerAd == null || !_isAdLoaded) {
      return null;
    }

    return Container(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  void dispose() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isAdLoaded = false;
  }
}