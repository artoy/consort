package edu.kyoto.fos.regnant.myTranslation;

import edu.kyoto.fos.regnant.cfg.BasicBlock;
import edu.kyoto.fos.regnant.cfg.CFGReconstructor;

import java.io.BufferedWriter;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;

// TODO: 関数呼び出しを return にする, あと配列を代入するのに * を消す, あと括弧の有無を考える (ConSORT の書き方を見る)
// TODO: 引数部分を作る
// TODO: 変換する JAVA プログラムによっては function3 とかが最初に来てしまって基本ブロックの最初に変数定義が来なくなってしまう場合がある. Regnant のプログラムを見てどの順番で来るかを理解しなければならない
// TODO: headOfFunction を BasicBlockGraph のメソッドに置き換えられないか
// TODO: 変換後のプログラムに main を加える
// TODO: 前生成したプログラムを消してから出力するようにする
// TODO: 無駄な Unit を減らす (関数呼び出しの後の Unit とか)
// TODO: 無駄な基本ブロックを減らす (return 文だけの基本ブロックが大量に生成される. もしかしたら検証器には嬉しかったりするのか？)
// TODO: オブジェクト指向の部分を big tuple で命令型言語に置き換えるようにする (もしかしたら CFGReconstructor の時点でできているのかも)
// TODO: alias 文を自動で挿入するようにする
// TODO: 基本ブロックの初めのところ (変換後は関数になる) 以外にも引数を入れる
// TODO: もしかしたら関数の返り値を伝える必要があるかも
// TODO: GotoStmt は基本ブロックとして分けないようにする

// ConSORT プログラムに変換された関数を表すクラス
public class TranslatedFunction {
  private final List<TranslatedBasicBlock> translatedFunction = new ArrayList<>();
  private List<String> allArguments = new ArrayList<>();
  private List<String> allBound = new ArrayList<>();

  public TranslatedFunction(CFGReconstructor cfg) {
    // 基本ブロックを出力
    System.out.println(cfg.dump());

    List<BasicBlock> basicBlocks = new ArrayList<>(cfg.getBbm().getHdMap().values());
    for (BasicBlock block : basicBlocks) {
      List<BasicBlock> nextBasicBlocks = cfg.getBbg().getSuccsOf(block);

      if (cfg.getBbg().getHeads().contains(block)) {
        // 関数のはじめの基本ブロックだけ headOfFunction を true にし, arguments を TranslatedFunction に返す
        TranslatedBasicBlock headBasicBlock = new TranslatedBasicBlock(block, true, nextBasicBlocks);
        this.translatedFunction.add(headBasicBlock);
        this.allArguments = Stream.concat(allArguments.stream(), headBasicBlock.getArguments().stream())
                .collect(Collectors.toList());
        this.allBound = Stream.concat(allBound.stream(), headBasicBlock.getBound().stream())
                .collect(Collectors.toList());
      } else {
        // 返ってきた arguments を他の基本ブロックに渡す
        TranslatedBasicBlock basicBlock = new TranslatedBasicBlock(block, false, nextBasicBlocks);
        this.translatedFunction.add(basicBlock);
        this.allArguments = Stream.concat(allArguments.stream(), basicBlock.getArguments().stream())
                .collect(Collectors.toList());
        this.allBound = Stream.concat(allBound.stream(), basicBlock.getBound().stream())
                .collect(Collectors.toList());
      }
    }
  }

  // 変換後の関数をファイルに書き込むためのメソッド
  public void print(String path) {
    // 変換後の関数を文字列にする
    String functionString = translatedFunction.stream().map(bb -> bb.print(allArguments, allBound)).collect(Collectors.joining("\n"));

    try (PrintWriter pw = new PrintWriter(new BufferedWriter(new OutputStreamWriter(new FileOutputStream(path, true), StandardCharsets.UTF_8)))) {
      // ファイルへの書き込み
      pw.println(functionString);
    } catch (IOException ex) {
      System.err.println(ex);
    }
  }
}
