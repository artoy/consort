package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import soot.jimple.internal.JimpleLocal;

// 変換された JimpleLocal を表す
public class Variable implements TranslatedValue{
  // variable は JimpleLocal そのものを表す
  private JimpleLocal variable;

  public Variable(JimpleLocal variable) {
    this.variable = variable;
  }

  // TBD: 変数をポインタのまま扱うときはそのまま toString すれば良いので、 isPointer = true の場合は存在しない
  public String print(boolean isPointer) {
    StringBuilder builder = new StringBuilder();
    if (!isPointer) builder.append("*");
    builder.append(variable.toString());

    return builder.toString();
  }
}
