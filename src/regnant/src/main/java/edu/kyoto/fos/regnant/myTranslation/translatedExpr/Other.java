package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import soot.Value;

public class Other implements TranslatedValue{
  private Value value;

  public Other(Value value) {
    this.value = value;
  }

  public String print(boolean isPointer) {
    return value.toString();
  }
}
