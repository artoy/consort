package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.matchingHandler.MatchingExprHandler;
import soot.jimple.AddExpr;

public class Add implements TranslatedValue{
  private TranslatedValue leftOp;
  private TranslatedValue rightOp;

  public Add(AddExpr e) {
    MatchingExprHandler handler = new MatchingExprHandler();

    this.leftOp = handler.translate(e.getOp1());
    this.rightOp = handler.translate(e.getOp2());
  }

  public String print(boolean isPointer) {
    StringBuilder builder = new StringBuilder();
    builder
      .append(leftOp.print(false))
      .append(" + ")
      .append(rightOp.print(false));

    return builder.toString();
  }
}
