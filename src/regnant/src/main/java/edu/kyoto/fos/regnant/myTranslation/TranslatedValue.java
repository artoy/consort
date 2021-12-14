package edu.kyoto.fos.regnant.myTranslation;

// 変換後の value (Expr) を表すインターフェース
public interface TranslatedValue {
  // Regnant における抽象構文木から ConSORT プログラムに変換するメソッド
  public String print(boolean isPointer);
}
