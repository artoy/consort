package edu.kyoto.fos.regnant.myTranslation;

public interface TranslatedUnit {
  public boolean isSequencing();
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


  default boolean istTranslatedUnitEmpty() {
    return print().length() == 0;
  }
}
