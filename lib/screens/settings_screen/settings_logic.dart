// לוגיקה טהורה למסך הגדרות

/// האם הגיע למספר לחיצות הנדרש לפתיחת Developer Mode
bool isDevModeUnlock(int tapCount, int threshold) => tapCount >= threshold;
