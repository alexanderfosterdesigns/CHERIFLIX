enum MaturityTier {
  kids,
  teen,
  mature,
}

extension MaturityTierCodec on MaturityTier {
  String get wireValue {
    switch (this) {
      case MaturityTier.kids:
        return 'kids';
      case MaturityTier.teen:
        return 'teen';
      case MaturityTier.mature:
        return 'mature';
    }
  }

  static MaturityTier fromWireValue(String value) {
    return switch (value) {
      'kids' => MaturityTier.kids,
      'teen' => MaturityTier.teen,
      _ => MaturityTier.mature,
    };
  }
}
