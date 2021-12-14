package edu.kyoto.fos.regnant.myTranslation;

// 変換後の Unit (Stmt) を表すインターフェース
public interface TranslatedUnit {
  // 次の命令が逐次に実行されるかどうか (命令の返り値が unit (void) かどうか, 命令の末尾に 「;」 が来るなら true, 「in」 が来るなら false)
  public boolean isSequencing();
  // Regnant における抽象構文木から ConSORT プログラムに変換するメソッド
  public String print();

  // インデントをつけて変換後の Unit を出力するメソッド
  default String printWithIndent(int indentLevel) {
    StringBuilder builder = new StringBuilder();
  
    for (int i = 0; i < indentLevel; i++) {
      builder.append("  ");
    }
  
    builder.append(print());
    
    return builder.toString();
  }

  // 変換後の Stmt が ConSORT プログラムに反映されるかどうか (されなかったら true)
  default boolean istTranslatedUnitEmpty() {
    return print().length() == 0;
  }
}
