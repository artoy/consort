package edu.kyoto.fos.regnant.myTranslation;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.myTranslation.matchingHandler.MatchingStmtHandler;

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

    boolean prevSequence = false;
    int indentLevel = 1;

    for (int i = 0; i < basicBlock.units.size(); i++) {
      // インデントレベルは必ず1以上
      assert(indentLevel > 0);

      if (i == basicBlock.units.size() - 1){
        // TODO: 関数呼び出しへの変換方法を考える
        TranslatedUnit tailTranslatedUnit = handler.translate(basicBlock.units.get(i), headOfFunction);
        translatedBasicBlock.add(tailTranslatedUnit);
      } else {
        TranslatedUnit translatedUnit = handler.translate(basicBlock.units.get(i), headOfFunction);

        // 逐次実行かそうでないかでインデントと {} を付ける
        if (prevSequence == false && translatedUnit.isSequencing() == true) {
          translatedUnit.beginSequencing = true;
          translatedUnit.endSequencing = false;
          translatedUnit.indentLevel++;
        } else if (prevSequence == true && translatedUnit.isSequencing() == false) {
          translatedUnit.beginSequencing = false;
          translatedUnit.endSequencing = true;
          translatedUnit.indentLevel--;
        } else {
          translatedUnit.beginSequencing = false;
          translatedUnit.endSequencing = false;
        }

        // もし変換した unit が IdentityStmt だったら引数になる変数があるので, それを parameters フィールドに入れる
        translatedUnit.getOptionalArgument().ifPresent(parameters::add);

        translatedBasicBlock.add(translatedUnit);
      }
    }
  }


  // 基本ブロックを関数名と関数呼び出し付きで出力するメソッド
  public String print() {
    String parametersString = parameters.stream().collect(Collectors.joining(", "));
    String BasicBlocksString = translatedBasicBlock.stream().filter(unit -> !unit.istTranslatedUnitEmpty()).map(TranslatedUnit::print).collect(Collectors.joining("\n"));

    StringBuilder builder = new StringBuilder();
    builder
      .append("function")
      .append(id)
      .append("(")
      .append(parametersString)
      .append(") { \n")
      .append(BasicBlocksString)
      .append("\n}\n");

    return builder.toString();
  }
}
