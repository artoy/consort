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

// TODO: 関数呼び出しを実装する (元々の関数名を残しておいた方がやりやすそう)
// TODO: if と goto を関数呼び出しで実装する (BasicBlockMapper.java を変更することになるかもしれん)
// TODO: 変換後のプログラムに main を加える
// TODO: 前生成したプログラムを消してから出力するようにする
// TODO: 無駄な Unit を減らす (関数呼び出しの後の Unit とか)
// TODO: 無駄な基本ブロックを減らす (return 文だけの基本ブロックが大量に生成される. もしかしたら検証器には嬉しかったりするのか？)

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
