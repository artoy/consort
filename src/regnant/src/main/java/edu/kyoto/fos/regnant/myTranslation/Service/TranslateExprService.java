package edu.kyoto.fos.regnant.myTranslation.Service;

import edu.kyoto.fos.regnant.myTranslation.TranslatedValue;
import edu.kyoto.fos.regnant.myTranslation.translatedExpr.Add;
import edu.kyoto.fos.regnant.myTranslation.translatedExpr.Mult;
import edu.kyoto.fos.regnant.myTranslation.translatedExpr.Other;
import edu.kyoto.fos.regnant.myTranslation.translatedExpr.Variable;

import soot.Value;
import soot.jimple.AddExpr;
import soot.jimple.MulExpr;
import soot.jimple.internal.JimpleLocal;

// Expr を場合分けするためのクラス
public class TranslateExprService {
  // Expr を場合分けして変換するメソッド
  public TranslatedValue translate(Value value) {
    if (value instanceof AddExpr) {
      return new Add((AddExpr)value);
    } else if (value instanceof MulExpr) {
      return new Mult((MulExpr)value);
    } else if (value instanceof JimpleLocal) {
      return new Variable((JimpleLocal)value);
    } else {
      return new Other(value);
    }
  }
}
