package edu.kyoto.fos.regnant.myTranslation.matchingHandler;

import edu.kyoto.fos.regnant.myTranslation.TranslatedUnit;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.AssertFail;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.Return;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.ReturnVoid;
import soot.Unit;
import soot.jimple.ArrayRef;
import soot.jimple.AssignStmt;
import soot.jimple.IdentityStmt;
import soot.jimple.IntConstant;
import soot.jimple.NopStmt;
import soot.jimple.ReturnStmt;
import soot.jimple.ReturnVoidStmt;
import soot.jimple.internal.JNewArrayExpr;
import soot.jimple.internal.JimpleLocal;

public class MatchingStmtHandler {
  
  public TranslatedUnit translate(Unit unit, boolean headOfFunction) {
    // Java SE 12 以降も使えるようにしたら switch 文に書き換える
    if (unit instanceof NopStmt) {
      // nop の場合 (assert が失敗した場合)
      return new AssertFail();
    } else if (unit instanceof ReturnVoidStmt) {
      // 何も返さない return 文の場合
      return new ReturnVoid();
    } else if (unit instanceof ReturnStmt) {
      // 値を返す return 文の場合
      return new Return(((ReturnStmt)unit).getOp());
    } else if (unit instanceof IdentityStmt) {
      // メソッドの引数は IdentityStmt で定義されるからその情報を argument に入れる
      this.argument = ((IdentityStmt)unit).getLeftOp().toString();
    } else if (unit instanceof AssignStmt) {
      // 代入文の場合
      AssignStmt assignUnit = (AssignStmt)unit;

      if (assignUnit.getRightOp() instanceof JNewArrayExpr) {
        // 配列を新しく作る場合
        // TODO: 配列の大きさが変数の場合にも対応する (* を付ける)
        builder
          .append("let ")
          .append(assignUnit.getLeftOp().toString())
          .append(" = mkarray ")
          .append(((JNewArrayExpr)(assignUnit.getRightOp())).getSize().toString())
          .append(" in");
      } else if (assignUnit.getLeftOp() instanceof ArrayRef) {
        // 配列の要素を更新する場合 (もし初期化の場合のみ <- を使うとかだったら要修正)
        builder
          .append(((ArrayRef)(assignUnit.getLeftOp())).getBase().toString())
          .append("[")
          .append(((ArrayRef)(assignUnit.getLeftOp())).getIndex().toString())
          .append("] <- ")
          .append(assignUnit.getRightOp())
          .append(";");

        this.isSequencing = true;
      } else if (assignUnit.getLeftOp() instanceof JimpleLocal && assignUnit.getRightOp() instanceof IntConstant && headOfFunction) {
        // 初めて変数が定義される場合 (関数の中の最初の基本ブロックに変数定義が全て含まれているという仮説による)
        // TODO: mkref の後に変数が来た場合も対応する
        builder
          .append("let ")
          .append(assignUnit.getLeftOp().toString())
          .append(" = mkref ")
          .append(assignUnit.getRightOp().toString())
          .append(" in");
      } else if (assignUnit.getLeftOp() instanceof JimpleLocal && assignUnit.getRightOp() instanceof IntConstant) {
        // 定義されている変数に値を代入する場合
        // TODO: := の後に変数が来た場合にも対応する
        builder
          .append(assignUnit.getLeftOp().toString())
          .append(" := ")
          .append(assignUnit.getRightOp().toString())
          .append(";");

          this.isSequencing = true;
      // TODO: InvokeStmt にも対応する
      } else {
        // throw new RuntimeException("This AssignStmt is not yet supported: " + unit + " ( Left: " + assignUnit.getLeftOp().getClass().toString() + " Right: " + assignUnit.getRightOp().getClass().toString() + ")");
        // デバッグのための, エラーの代わりの標準出力
        builder
          .append("This AssignStmt is not yet supported: ")
          .append(unit.toString())
          .append(" ( Left: ")
          .append(assignUnit.getLeftOp().getClass().toString())
          .append(" Right: ")
          .append(assignUnit.getRightOp().getClass().toString())
          .append(")");
      }
    } else {
      // throw new RuntimeException("This unit is not yet supported: " + unit + " (" + unit.getClass() + ")");
      // デバッグのための, エラーのための標準出力
      builder
        .append("This unit is not yet supported: ")
        .append(unit)
        .append(" (")
        .append(unit.getClass())
        .append(")");
    }

    this.translatedUnit = builder.toString();
  }
}
