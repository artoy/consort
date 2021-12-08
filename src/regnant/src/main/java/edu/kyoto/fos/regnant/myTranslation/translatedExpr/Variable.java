package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import soot.jimple.internal.JimpleLocal;

public class Variable implements TranslatedValue{
  private JimpleLocal variable;

  public Variable(JimpleLocal variable) {
    this.variable = variable;
  }

  // TBD: 今の所ポインタが代入の右辺に出現しないので isPointer = true の場合は存在しない
  public String print(boolean isPointer) {
    StringBuilder builder = new StringBuilder();
    if (!isPointer) builder.append("*");
    builder.append(variable.toString());

    return builder.toString();
  }
}
