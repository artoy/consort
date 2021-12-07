package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import soot.jimple.internal.JimpleLocal;

public class Variable implements TranslatedValue{
  private JimpleLocal variable;
  private boolean isPointer;

  public Variable(JimpleLocal variable, boolean isPointer) {
    this.variable = variable;
    this.isPointer = isPointer;
  }

  public String print() {
    StringBuilder builder = new StringBuilder();
    if (!isPointer) builder.append("*");
    builder.append(variable.toString());

    return builder.toString();
  }
}
