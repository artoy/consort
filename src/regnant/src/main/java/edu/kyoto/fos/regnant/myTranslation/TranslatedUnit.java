package edu.kyoto.fos.regnant.myTranslation;

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

import java.util.Optional;

// ConSORT プログラムに変換された Unit を表すクラス
public class TranslatedUnit {
  // translatedUnit は変換後の Unit, argument は unit が IdentityStmt だった時のメソッドの引数, isSequencing は逐次実行であるか否か ({} と インデントが必要かの判定に必要), indentLevel は何回インデントをするか (tab 換算)
  private String translatedUnit;
  private String argument;
  // private String declaredVariable;
  private boolean isSequencing = false;
  public boolean beginSequencing = false;
  public boolean endSequencing = false;
  public int indentLevel;


  public TranslatedUnit(Unit unit, boolean headOfFunction, int indentLevel) {
    this.indentLevel = indentLevel;

    StringBuilder builder = new StringBuilder();
    // Java SE 12 以降も使えるようにしたら switch 文に書き換える
    if (unit instanceof NopStmt) {
      // nop の場合 (assert が失敗した場合)
      builder.append("fail;");
    } else if (unit instanceof ReturnVoidStmt) {
      // 何も返さない return 文の場合
      builder.append("return 0");
    } else if (unit instanceof ReturnStmt) {
      // 値を返す return 文の場合
      builder
        .append("return ")
        .append(((ReturnStmt)unit).getOp().toString());
    } else if (unit instanceof IdentityStmt) {
      // メソッドの引数の定義の場合
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


  // 変換後の Unit をインデントを付けて出力するメソッド
  public String print() {
    StringBuilder builder = new StringBuilder();

    for (int i = 0; i < indentLevel; i++) {
      builder.append("  ");
    }

    builder.append(translatedUnit);
    
    return builder.toString();
  }


  // unit が IdentityStmt の時は := の左辺は関数の引数になるので, その情報を渡すためのメソッド
  public Optional<String> getOptionalArgument() {
    return Optional.ofNullable(argument);
  }


  // // unit が AssignStmt の時に, = の左辺の変数を渡すためのメソッド
  // public Optional<String> getOptionalDeclaredVariable() {
  //   return Optional.ofNullable(declaredVariable);
  // }


  // isSequencing を渡すためのメソッド
  public boolean getIsSequencing() {
    return isSequencing;
  }


  // // indentLevel を渡すためのメソッド
  // public int getIndentLevel() {
  //   return indentLevel;
  // }


  // 変換後の unit が空であるかどうかを判定するメソッド
  public boolean istTranslatedUnitEmpty() {
    return translatedUnit.length() == 0;
  }
}
