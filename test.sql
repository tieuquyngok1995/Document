SET QUOTED_IDENTIFIER ON
GO
SET ANSI_NULLS ON
GO

/**************************************************************************************************
*
* システム              ：ZeeM人事給与システム
* サブシステム          ：合併に伴うシステム更新
* 機能                  ：人事考課累積ファイル
* ファンクション        ：ZVTTEKOUKA_MAIN
*--------------------------------------------------------------------------------------------------
* Copyright: All Rights Reserved,Copyright CREO Co.,LTD. 2003-2025
*--------------------------------------------------------------------------------------------------
* 作成日                ：2025/12/01
* 作成者                ：FJS Tuan-VQ
*--------------------------------------------------------------------------------------------------
*【要件】
*・移行基準日時点でSJMTKIHON.在籍区分が'1'か'8'か'9'の社員番号　※1：在籍　8：休職　9：退職
*・社員番号に紐づくSJTTKOUKAH(考課結果)が存在する事、考課の情報はSJTTKUOKAH.考課種別='1'、'2'、'3'が対象、
*  片方しかない場合、存在しない方の値は初期値(NULLまたは0)とする　※1：人事考課　2：賞与考課 3：業績考課（基準＋職務）
*・SJMTKIHON.社員番号、SJTTKOUKAH.考課年度毎に1レコードを作成(考課情報が存在しない考課年度は作成しない事になる)
*--------------------------------------------------------------------------------------------------
* 【引数】
*    1 移行基準日： VARCHAR(10) - 移行基準日
*--------------------------------------------------------------------------------------------------
*【変更履歴】
* 更新番号      管理番号    変更内容                    Ver     日付            担当者
**************************************************************************************************/

IF EXISTS (
    SELECT *
FROM dbo.sysobjects
WHERE id = object_id(N'[ZVTTEKOUKA_MAIN]') AND OBJECTPROPERTY(id, N'IsProcedure') = 1
)
    DROP PROCEDURE [ZVTTEKOUKA_MAIN]
GO

CREATE PROCEDURE [ZVTTEKOUKA_MAIN]
    @wv_ikou_kijunbi  VARCHAR(10)
AS
BEGIN
    /*--- 開始処理 ---*/
    SET LANGUAGE Japanese;
    SET NOCOUNT ON;

    /*----------------------------------------------------------------------------*
    * エラー処理用変数を宣言する
    *-----------------------------------------------------------------------------*/
    DECLARE @wv_program_name              VARCHAR(60);  -- プログラム名
    DECLARE @wc_message_level             CHAR(1);      -- メッセージレベル
    DECLARE @wv_message                   VARCHAR(max); -- メッセージ
    DECLARE @wv_message_err               VARCHAR(max); -- エーラメッセージ

    /*----------------------------------------------------------------------------*
    * 更新処理用変数を宣言する
    *-----------------------------------------------------------------------------*/
    DECLARE @wi_insert_count              INT;          -- ZVTTEKOUKA挿入件数
    DECLARE @wv_i_shain_no                VARCHAR(9);   -- 社員番号
    DECLARE @wv_i_sei                     VARCHAR(30);  -- 姓
    DECLARE @wv_i_mei                     VARCHAR(30);  -- 名
    DECLARE @wv_i_sei_mei                 VARCHAR(22);  -- 氏名
    DECLARE @wv_i_jisshi_nendo            VARCHAR(4);   -- 実施年度
    DECLARE @wv_i_kettei_shoyo_seika      VARCHAR(3);   -- 決定賞与(成果)評定
    DECLARE @wv_i_kettei_kodo             VARCHAR(3);   -- 決定行動評定
    DECLARE @wv_i_tokyu_meisho            VARCHAR(30);  -- 等級名称
    DECLARE @wv_i_shain_kbn_ryakusho      VARCHAR(18);  -- 社員区分略称
    DECLARE @wv_i_yakuwari_kubun_ryakusho VARCHAR(18);  -- 役割区分略称
    DECLARE @wv_i_tekiyo                  VARCHAR(255); -- 摘要
    DECLARE @wv_i_shokumu_grade_ryakusho  VARCHAR(255); -- 職務ｸﾞﾚｰﾄﾞ略称

    /*----------------------------------------------------------------------------*
    * 論理処理用変数を宣言する
    *-----------------------------------------------------------------------------*/
    DECLARE @wv_shain_no                  VARCHAR(10);  -- 社員番号
    DECLARE @wv_sei                       VARCHAR(30);  -- 姓
    DECLARE @wv_mei                       VARCHAR(30);  -- 名
    DECLARE @wv_koka_nendo                VARCHAR(10);  -- 考課年度
    DECLARE @wv_koka_shubetsu             VARCHAR(10);  -- 考課種別
    DECLARE @wd_koka_kijunbi              VARCHAR(10);  -- 考課基準日
    DECLARE @wv_sogo_hyoka_1              VARCHAR(10);  -- 総合評価
    DECLARE @wv_sogo_hyoka_2              VARCHAR(10);  -- 総合評価
    DECLARE @wv_sogo_hyoka_3              VARCHAR(10);  -- 総合評価
    DECLARE @wv_shokumu_tokyu_code        VARCHAR(10);  -- 職務等級コード
    DECLARE @wv_shokuno_tokyu_code        VARCHAR(10);  -- 職能等級コード
    DECLARE @wv_yakushoku_code            VARCHAR(10);  -- 役職コード
    DECLARE @wv_henkan                    VARCHAR(MAX);

    /*----------------------------------------------------------------------------*
    * 初期値をセットする
    *-----------------------------------------------------------------------------*/
    SET @wv_program_name    = '人事考課累積ファイル';
    SET @wi_insert_count    = 0;

    /*----------------------------------------------------------------------------*
    * １．初期処理 *
    *-----------------------------------------------------------------------------*/
    SET @wc_message_level = 'I';
    SET @wv_message = '移行データの編集・TBL出力を開始します';
    EXEC dbo.ZVTTLOG_MAIN
        @wv_program_name,
        @wc_message_level,
        @wv_message;

    /*----------------------------------------------------------------------------*
    * ２．起動パラメータ *
    *-----------------------------------------------------------------------------*/
    IF (@wv_ikou_kijunbi  IS NULL)
    BEGIN
        SET @wc_message_level = 'E';
        SET @wv_message = 'パラメータがありません。';
        EXEC dbo.ZVTTLOG_MAIN
            @wv_program_name,
            @wc_message_level,
            @wv_message;
        RETURN;
    END;