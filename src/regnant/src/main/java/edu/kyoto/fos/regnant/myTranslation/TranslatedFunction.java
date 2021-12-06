package edu.kyoto.fos.regnant.myTranslation;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.cfg.CFGReconstructor;

import java.io.BufferedWriter;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

// ConSORT プログラムに変換された関数を表すクラス
public class TranslatedFunction {
  private List<TranslatedBasicBlock> translatedFunction = new ArrayList<>();


  public TranslatedFunction(CFGReconstructor cfg) {
    // 基本ブロックを出力
    System.out.println(cfg.dump());

    List<BasicBlock> basicBlocks = new ArrayList<>(cfg.getBbm().getHdMap().values());
    for (int i = 0; i < basicBlocks.size(); i++) {
      if (i == 0) { 
        // 関数のはじめの基本ブロックだけ headOfFunction を true にする
        TranslatedBasicBlock headBasicBlock = new TranslatedBasicBlock(basicBlocks.get(i), true);
        this.translatedFunction.add(headBasicBlock);
      } else {
        TranslatedBasicBlock basicBlock = new TranslatedBasicBlock(basicBlocks.get(i), false);
        this.translatedFunction.add(basicBlock);
      }
    }
  }


  // 変換後の関数をファイルに書き込むためのメソッド
  public void print(String path) {
    // 変換後の関数を文字列にする
    String functionString = translatedFunction.stream().map(TranslatedBasicBlock::print).collect(Collectors.joining("\n"));

    try (PrintWriter pw = new PrintWriter(new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path, true),"utf-8")));) {
      // ファイルへの書き込み
      pw.println(functionString);
    } catch (IOException ex) {
      System.err.println(ex);
    }
  }
}
