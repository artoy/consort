package edu.kyoto.fos.regnant.myTranslation;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.myTranslation.Service.TranslateStmtService;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.Argument;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.Goto;
import edu.kyoto.fos.regnant.myTranslation.translatedStmt.If;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

// ConSORT プログラムに変換された基本ブロックを表すためのクラス
public class TranslatedBasicBlock {
  // id は基本ブロックのナンバリング, translatedBasicBlock は変換後の式のリスト, arguments は変換後の基本ブロックの関数の引数
  private int id;
  private List<TranslatedUnit> translatedBasicBlock = new ArrayList<>();
  private List<String> arguments = new ArrayList<>();
  private List<BasicBlock> nextBasicBlocks;

  public TranslatedBasicBlock(BasicBlock basicBlock, boolean headOfFunction, List<BasicBlock> nextBasicBlocks) {
    TranslateStmtService service = new TranslateStmtService();

    this.id = basicBlock.id;
    this.nextBasicBlocks = nextBasicBlocks;

    for (int i = 0; i < basicBlock.units.size(); i++) {
      TranslatedUnit translatedUnit = service.translate(basicBlock.units.get(i), headOfFunction, nextBasicBlocks);

      // もし変換後の unit が Argument だった場合, 引数になる変数があるので, それを parameters フィールドに入れる
      if (translatedUnit instanceof Argument) arguments.add(((Argument)translatedUnit).getArgumentVariable());

      translatedBasicBlock.add(translatedUnit);
    }
  }

  // 波括弧の左側を付けるためのメソッド
  private String printLeftBraces(int indentLevel) {
    StringBuilder builder = new StringBuilder();

    for (int i = 0; i < indentLevel; i++) {
      builder.append("  ");
    }

    builder.append("{");

    return builder.toString();
  }

  // 波括弧の右側を付けるためのメソッド
  private String printRightBraces(int indentLevel) {
    StringBuilder builder = new StringBuilder();

    // 波括弧の右側は必ず基本ブロックの最後にくるのでインデントの個数から付ける波括弧の個数を判別する
    for (int i = indentLevel; i > 0; i--) {
      for (int j = 0; j < i; j++) {
        builder.append("  ");
      }

      builder.append("}\n");
    }

    return builder.toString();
  }

  // 基本ブロックの最後の Unit を得るメソッド
  private TranslatedUnit getTail() {
    return translatedBasicBlock.get(translatedBasicBlock.size() - 1);
  }

  // 基本ブロックを関数名と関数呼び出し付きで出力するメソッド
  public String print() {
    // 引数部分の作成
    String parametersString = arguments.stream().collect(Collectors.joining(", "));

    // 関数の中身の作成. ただし右の波括弧は末尾の関数呼び出しの後に入れたいので最後に回している
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

    String basicBlocksString = basicBlocksBuilder.toString();

    // 次の基本ブロックを呼び出す部分の作成
    StringBuilder nextBasicBlockBuilder = new StringBuilder();

    if (!(getTail() instanceof If || getTail() instanceof Goto || nextBasicBlocks.size() == 0)) {
      for (int i = 0; i < indentLevel; i++) {
        nextBasicBlockBuilder.append("  ");
      }

      assert(nextBasicBlocks.size() == 1);

      nextBasicBlockBuilder
        .append("return ")
        .append("function")
        .append(nextBasicBlocks.get(0).id)
        .append("(")
        .append(")\n");
    }

    String nextBasicBlock = nextBasicBlockBuilder.toString();

    // 結合
    StringBuilder builder = new StringBuilder();
    builder
      .append("function")
      .append(id)
      .append("(")
      .append(parametersString)
      .append(") { \n")
      .append(basicBlocksString)
      .append(nextBasicBlock)
      .append(printRightBraces(indentLevel - 1))
      .append("}\n");

    return builder.toString();
  }
}
