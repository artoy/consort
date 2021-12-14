package edu.kyoto.fos.regnant.myTranslation.translatedExpr;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.Service.TranslateExprService;
import soot.jimple.AddExpr;

// 変換された AddExpr を表すクラス
public class Add implements TranslatedValue{
  // leftOp は1つ目のオペランド, rightOp は2つ目のオペランドを表す
  private TranslatedValue leftOp;
  private TranslatedValue rightOp;

  public Add(AddExpr e) {
    TranslateExprService service = new TranslateExprService();

    this.leftOp = service.translate(e.getOp1());
    this.rightOp = service.translate(e.getOp2());
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
