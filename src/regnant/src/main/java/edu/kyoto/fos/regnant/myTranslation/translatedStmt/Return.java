package edu.kyoto.fos.regnant.myTranslation.translatedStmt;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import soot.Value;
import soot.jimple.internal.JReturnStmt;

// ある値を返す return 文のクラス
public class Return implements TranslatedUnit {
  // returnValue は返り値
  private Value returnValue;

  public Return(JReturnStmt unit) {
    this.returnValue = unit.getOp();
  }

  public boolean isSequencing() {
    return false;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    builder
      .append("return ")
      .append(returnValue.toString());

    return builder.toString();
  }
}