package edu.kyoto.fos.regnant.myTranslation;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.myTranslation.matchingHandler.MatchingStmtHandler;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.Argument;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

// ConSORT プログラムに変換された基本ブロックを表すためのクラス
public class TranslatedBasicBlock {
  private int id;
  private List<TranslatedUnit> translatedBasicBlock = new ArrayList<>();
  private List<String> parameters = new ArrayList<>();


  public TranslatedBasicBlock(BasicBlock basicBlock, boolean headOfFunction) {
    MatchingStmtHandler handler = new MatchingStmtHandler();

    this.id = basicBlock.id;

    for (int i = 0; i < basicBlock.units.size(); i++) {
      if (i == basicBlock.units.size() - 1){
        // TODO: 関数呼び出しへの変換方法を考える
        TranslatedUnit tailTranslatedUnit = handler.translate(basicBlock.units.get(i), headOfFunction);
        translatedBasicBlock.add(tailTranslatedUnit);
      } else {
        TranslatedUnit translatedUnit = handler.translate(basicBlock.units.get(i), headOfFunction);

        // もし変換した unit が IdentityStmt だったら引数になる変数があるので, それを parameters フィールドに入れる
        if (translatedUnit instanceof Argument) parameters.add(((Argument)translatedUnit).getArgumentVariable());

        translatedBasicBlock.add(translatedUnit);
      }
    }
  }

  private String printLeftBraces(int indentLevel) {
    StringBuilder builder = new StringBuilder();

    for (int i = 0; i < indentLevel; i++) {
      builder.append("  ");
    }

    builder.append("{");

    return builder.toString();
  }

  private String printRightBraces(int indentLevel) {
    StringBuilder builder = new StringBuilder();

    for (int i = indentLevel; i > 0; i--) {
      for (int j = 0; j < i; j++) {
        builder.append("  ");
      }

      builder.append("}\n");
    }

    return builder.toString();
  }


  // 基本ブロックを関数名と関数呼び出し付きで出力するメソッド
  public String print() {
    String parametersString = parameters.stream().collect(Collectors.joining(", "));

    boolean prevSequence = true;
    int indentLevel = 1;
    StringBuilder basicBlocksBuilder = new StringBuilder();
    for (int i = 0; i < translatedBasicBlock.size(); i++) {
      TranslatedUnit translatedUnit = translatedBasicBlock.get(i);

      if (!translatedUnit.istTranslatedUnitEmpty()) {
        if (translatedUnit.isSequencing() && !prevSequence) {
          indentLevel++;

          basicBlocksBuilder
            .append(printLeftBraces(indentLevel - 1))
            .append("\n")
            .append(translatedUnit.printWithIndent(indentLevel))
            .append("\n");
        } else {
          basicBlocksBuilder
            .append(translatedUnit.printWithIndent(indentLevel))
            .append("\n");
        }
      }

      prevSequence = translatedUnit.isSequencing();
    }

    basicBlocksBuilder.append(printRightBraces(indentLevel - 1));

    String basicBlocksString = basicBlocksBuilder.toString();

    StringBuilder builder = new StringBuilder();
    builder
      .append("function")
      .append(id)
      .append("(")
      .append(parametersString)
      .append(") { \n")
      .append(basicBlocksString)
      .append("}\n");

    return builder.toString();
  }
}
