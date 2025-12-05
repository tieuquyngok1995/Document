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

    /*----------------------------------------------------------------------------*
    * ３．処理詳細 *
    *-----------------------------------------------------------------------------*/
    /*-- ３．１．出力テーブルのデータ削除 --*/
    DELETE FROM dbo.ZVTTEKOUKA;

    /*-- ３．２．ローカル一時テーブルの作成 --*/
    SELECT
        管理コード,
        摘要
    INTO #TBL_ZVMTCODECV_014
    FROM CRO_GET_ZVMTCODECV('10', 'HENKAN0014');

    SELECT
        管理コード,
        摘要
    INTO #TBL_ZVMTCODECV_015
    FROM CRO_GET_ZVMTCODECV('10', 'HENKAN0015');

    SELECT
        管理コード,
        摘要
    INTO #TBL_ZVMTCODECV_042
    FROM CRO_GET_ZVMTCODECV('0', 'HENKAN0042');

    SELECT
        管理コード,
        テキスト５,
        摘要
    INTO #TBL_ZVMTCODECV_044
    FROM CRO_GET_ZVMTCODECV('10', 'HENKAN0044');

    SELECT
        管理コード,
        摘要
    INTO #TBL_ZVMTCODECV_045
    FROM CRO_GET_ZVMTCODECV('10', 'HENKAN0045');

    SELECT
        管理コード,
        テキスト５,
        摘要
    INTO #TBL_ZVMTCODECV_046
    FROM CRO_GET_ZVMTCODECV('10', 'HENKAN0046');

    SELECT
        摘要,
        適用開始日,
        適用終了日
    INTO #TBL_QCMTCODED
    FROM QCMTCODED
    WHERE 情報キー = 'SJMT092';

    /*-- ３．３．処理のメインとなるテーブルの抽出条件 --*/
    CREATE TABLE #TBL_ZVTTEKOUKA
    (
        [社員番号] VARCHAR(10) NOT NULL,
        [姓] VARCHAR(30) NULL,
        [名] VARCHAR(30) NULL,
        [考課年度] VARCHAR(10) NULL,
        [考課種別] VARCHAR(10) NULL,
        [考課基準日] CHAR(10) NULL,
        [総合評価_1] VARCHAR(10) NULL,
        [総合評価_2] VARCHAR(10) NULL,
        [総合評価_3] VARCHAR(10) NULL,
        [職務等級コード] VARCHAR(10) NULL,
        [職能等級コード] VARCHAR(10) NULL,
        [役職コード] VARCHAR(10) NULL
    );

    INSERT INTO #TBL_ZVTTEKOUKA
        SELECT
            SJMTKIHON.社員番号,
            KJMTKIHON.姓,
            KJMTKIHON.名,
            SJTTKOUKAH_1.考課年度,
            SJTTKOUKAH_1.考課種別,
            SJTTKOUKAH_1.考課基準日,
            SJTTKOUKAH_1.総合評価 AS 総合評価_1,
            SJTTKOUKAH_2.総合評価 AS 総合評価_2,
            SJTTKOUKAH_3.総合評価 AS 総合評価_3,
            HRMTSHIKAK.職務等級コード,
            HRMTSHIKAK.職能等級コード,
            HRMTYAKUSH.役職コード
        FROM SJMTKIHON AS SJMTKIHON -- 考課種別='1'が存在する
            INNER JOIN KJMTKIHON AS KJMTKIHON
                ON KJMTKIHON.個人識別ＩＤ = SJMTKIHON.個人識別ＩＤ
                AND KJMTKIHON.適用開始日 <= @wv_ikou_kijunbi
                AND KJMTKIHON.適用終了日 >= @wv_ikou_kijunbi
            INNER JOIN SJTTKOUKAH  AS SJTTKOUKAH_1 -- ※考課種別='1'を取得
                ON SJTTKOUKAH_1.会社コード = SJMTKIHON.会社コード
                AND SJTTKOUKAH_1.社員番号 = SJMTKIHON.社員番号
                AND SJTTKOUKAH_1.考課種別 = '1'
            LEFT JOIN SJTTKOUKAH AS SJTTKOUKAH_2 -- ※考課種別='2'を取得
                ON SJTTKOUKAH_2.会社コード = SJTTKOUKAH_1.会社コード
                AND SJTTKOUKAH_2.社員番号 = SJTTKOUKAH_1.社員番号
                AND SJTTKOUKAH_2.考課年度 = SJTTKOUKAH_1.考課年度
                AND SJTTKOUKAH_2.考課種別 = '2'
            LEFT JOIN SJTTKOUKAH AS SJTTKOUKAH_3 -- ※考課種別='3'を取得
                ON SJTTKOUKAH_3.会社コード = SJTTKOUKAH_1.会社コード
                AND SJTTKOUKAH_3.社員番号 = SJTTKOUKAH_1.社員番号
                AND SJTTKOUKAH_3.考課年度 = SJTTKOUKAH_1.考課年度
                AND SJTTKOUKAH_3.考課種別 = '3'
            INNER JOIN HRMTSHIKAK AS HRMTSHIKAK
                ON HRMTSHIKAK.会社コード = SJMTKIHON.会社コード
                AND HRMTSHIKAK.社員番号 = SJMTKIHON.社員番号
                AND HRMTSHIKAK.マスタ更新区分 = '1'
                AND HRMTSHIKAK.履歴有効区分 = '1'
                AND SJTTKOUKAH_1.考課基準日 BETWEEN HRMTSHIKAK.適用開始日 AND HRMTSHIKAK.適用終了日
            INNER JOIN HRMTYAKUSH AS HRMTYAKUSH
                ON HRMTYAKUSH.会社コード = SJMTKIHON.会社コード
                AND HRMTYAKUSH.社員番号 = SJMTKIHON.社員番号
                AND HRMTYAKUSH.マスタ更新区分 = '1'
                AND HRMTYAKUSH.履歴有効区分 = '1'
                AND SJTTKOUKAH_1.考課基準日 BETWEEN HRMTYAKUSH.適用開始日 AND HRMTYAKUSH.適用終了日
        WHERE SJMTKIHON.会社コード = '11'
            AND SJMTKIHON.適用開始日 <= @wv_ikou_kijunbi
            AND SJMTKIHON.適用終了日 >= @wv_ikou_kijunbi
            AND SJMTKIHON.在籍区分 IN ('1','8','9')
            AND SJTTKOUKAH_1.考課種別 = '1'
            AND SJTTKOUKAH_2.社員番号 IS NULL -- TODO:QA
            AND SJTTKOUKAH_3.社員番号 IS NULL
    UNION ALL
        -- 考課種別='2'が存在して、考課種別='1'、'3'が存在しない
        SELECT
            SJMTKIHON.社員番号,
            KJMTKIHON.姓,
            KJMTKIHON.名,
            SJTTKOUKAH_1.考課年度,
            SJTTKOUKAH_1.考課種別,
            SJTTKOUKAH_1.考課基準日,
            SJTTKOUKAH_1.総合評価 AS 総合評価_1,
            SJTTKOUKAH_2.総合評価 AS 総合評価_2,
            SJTTKOUKAH_3.総合評価 AS 総合評価_3,
            HRMTSHIKAK.職務等級コード,
            HRMTSHIKAK.職能等級コード,
            HRMTYAKUSH.役職コード
        FROM SJMTKIHON AS SJMTKIHON
            INNER JOIN KJMTKIHON AS KJMTKIHON
                ON KJMTKIHON.個人識別ＩＤ = SJMTKIHON.個人識別ＩＤ
                AND KJMTKIHON.適用開始日 <= @wv_ikou_kijunbi
                AND KJMTKIHON.適用終了日 >= @wv_ikou_kijunbi
            INNER JOIN SJTTKOUKAH  AS SJTTKOUKAH_1 -- ※考課種別='2'を取得
                ON SJTTKOUKAH_1.会社コード = SJMTKIHON.会社コード
                AND SJTTKOUKAH_1.社員番号 = SJMTKIHON.社員番号
                AND SJTTKOUKAH_1.考課種別 = '2'
            LEFT JOIN SJTTKOUKAH AS SJTTKOUKAH_2 -- ※考課種別='1'を取得
                ON SJTTKOUKAH_2.会社コード = SJTTKOUKAH_1.会社コード
                AND SJTTKOUKAH_2.社員番号 = SJTTKOUKAH_1.社員番号
                AND SJTTKOUKAH_2.考課年度 = SJTTKOUKAH_1.考課年度
                AND SJTTKOUKAH_2.考課種別 = '1'
            LEFT JOIN SJTTKOUKAH AS SJTTKOUKAH_3 -- ※考課種別='3'を取得
                ON SJTTKOUKAH_3.会社コード = SJTTKOUKAH_1.会社コード
                AND SJTTKOUKAH_3.社員番号 = SJTTKOUKAH_1.社員番号
                AND SJTTKOUKAH_3.考課年度 = SJTTKOUKAH_1.考課年度
                AND SJTTKOUKAH_3.考課種別 = '3'
            INNER JOIN HRMTSHIKAK AS HRMTSHIKAK
                ON HRMTSHIKAK.会社コード = SJMTKIHON.会社コード
                AND HRMTSHIKAK.社員番号 = SJMTKIHON.社員番号
                AND HRMTSHIKAK.マスタ更新区分 = '1'
                AND HRMTSHIKAK.履歴有効区分 = '1'
                AND SJTTKOUKAH_1.考課基準日 BETWEEN HRMTSHIKAK.適用開始日 AND HRMTSHIKAK.適用終了日
            INNER JOIN HRMTYAKUSH AS HRMTYAKUSH
                ON HRMTYAKUSH.会社コード = SJMTKIHON.会社コード
                AND HRMTYAKUSH.社員番号 = SJMTKIHON.社員番号
                AND HRMTYAKUSH.マスタ更新区分 = '1'
                AND HRMTYAKUSH.履歴有効区分 = '1'
                AND SJTTKOUKAH_1.考課基準日 BETWEEN HRMTYAKUSH.適用開始日 AND HRMTYAKUSH.適用終了日
        WHERE SJMTKIHON.会社コード = '11'
            AND SJMTKIHON.適用開始日 <= @wv_ikou_kijunbi
            AND SJMTKIHON.適用終了日 >= @wv_ikou_kijunbi
            AND SJMTKIHON.在籍区分 IN ('1','8','9')
            AND SJTTKOUKAH_1.考課種別 = '2'
            AND SJTTKOUKAH_2.社員番号 IS NULL -- TODO:QA
            AND SJTTKOUKAH_3.社員番号 IS NOT NULL
    UNION ALL
        -- 考課種別='3'が存在して、考課種別='1'、'2'が存在しない
        SELECT
            SJMTKIHON.社員番号,
            KJMTKIHON.姓,
            KJMTKIHON.名,
            SJTTKOUKAH_1.考課年度,
            SJTTKOUKAH_1.考課種別,
            SJTTKOUKAH_1.考課基準日,
            SJTTKOUKAH_1.総合評価 AS 総合評価_1,
            SJTTKOUKAH_2.総合評価 AS 総合評価_2,
            SJTTKOUKAH_3.総合評価 AS 総合評価_3,
            HRMTSHIKAK.職務等級コード,
            HRMTSHIKAK.職能等級コード,
            HRMTYAKUSH.役職コード
        FROM SJMTKIHON AS SJMTKIHON
            INNER JOIN KJMTKIHON AS KJMTKIHON
                ON KJMTKIHON.個人識別ＩＤ = SJMTKIHON.個人識別ＩＤ
                AND KJMTKIHON.適用開始日 <= @wv_ikou_kijunbi
                AND KJMTKIHON.適用終了日 >= @wv_ikou_kijunbi
            INNER JOIN SJTTKOUKAH  AS SJTTKOUKAH_1 -- ※考課種別='3'を取得
                ON SJTTKOUKAH_1.会社コード = SJMTKIHON.会社コード
                AND SJTTKOUKAH_1.社員番号 = SJMTKIHON.社員番号
                AND SJTTKOUKAH_1.考課種別 = '3'
            LEFT JOIN SJTTKOUKAH AS SJTTKOUKAH_2 -- ※考課種別='1'を取得
                ON SJTTKOUKAH_2.会社コード = SJTTKOUKAH_1.会社コード
                AND SJTTKOUKAH_2.社員番号 = SJTTKOUKAH_1.社員番号
                AND SJTTKOUKAH_2.考課年度 = SJTTKOUKAH_1.考課年度
                AND SJTTKOUKAH_2.考課種別 = '1'
            LEFT JOIN SJTTKOUKAH AS SJTTKOUKAH_3 -- ※考課種別='2'を取得
                ON SJTTKOUKAH_3.会社コード = SJTTKOUKAH_1.会社コード
                AND SJTTKOUKAH_3.社員番号 = SJTTKOUKAH_1.社員番号
                AND SJTTKOUKAH_3.考課年度 = SJTTKOUKAH_1.考課年度
                AND SJTTKOUKAH_3.考課種別 = '2'
            INNER JOIN HRMTSHIKAK AS HRMTSHIKAK
                ON HRMTSHIKAK.会社コード = SJMTKIHON.会社コード
                AND HRMTSHIKAK.社員番号 = SJMTKIHON.社員番号
                AND HRMTSHIKAK.マスタ更新区分 = '1'
                AND HRMTSHIKAK.履歴有効区分 = '1'
                AND SJTTKOUKAH_1.考課基準日 BETWEEN HRMTSHIKAK.適用開始日 AND HRMTSHIKAK.適用終了日
            INNER JOIN HRMTYAKUSH AS HRMTYAKUSH
                ON HRMTYAKUSH.会社コード = SJMTKIHON.会社コード
                AND HRMTYAKUSH.社員番号 = SJMTKIHON.社員番号
                AND HRMTYAKUSH.マスタ更新区分 = '1'
                AND HRMTYAKUSH.履歴有効区分 = '1'
                AND SJTTKOUKAH_1.考課基準日 BETWEEN HRMTYAKUSH.適用開始日 AND HRMTYAKUSH.適用終了日
        WHERE SJMTKIHON.会社コード = '11'
            AND SJMTKIHON.適用開始日 <= @wv_ikou_kijunbi
            AND SJMTKIHON.適用終了日 >= @wv_ikou_kijunbi
            AND SJMTKIHON.在籍区分 IN ('1','8','9')
            AND SJTTKOUKAH_1.考課種別 = '3'
            AND SJTTKOUKAH_2.社員番号 IS NULL -- TODO:QA
            AND SJTTKOUKAH_3.社員番号 IS NOT NULL;

    /*-- ３．４．各項目の編集 --*/
    DECLARE CUR_MAIN CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        社員番号,
        姓,
        名,
        考課年度,
        考課種別,
        考課基準日,
        総合評価_1,
        総合評価_2,
        総合評価_3,
        職務等級コード,
        職能等級コード,
        役職コード
    FROM #TBL_ZVTTEKOUKA AS ZVTTEKOUKA;

    OPEN CUR_MAIN;

    BEGIN TRANSACTION;

    BEGIN TRY
        /*-- 次の行フェッチ --*/
        FETCH NEXT FROM CUR_MAIN
            INTO @wv_shain_no,
                @wv_sei,
                @wv_mei,
                @wv_koka_nendo,
                @wv_koka_shubetsu,
                @wd_koka_kijunbi,
                @wv_sogo_hyoka_1,
                @wv_sogo_hyoka_2,
                @wv_sogo_hyoka_3,
                @wv_shokumu_tokyu_code,
                @wv_shokuno_tokyu_code,
                @wv_yakushoku_code;

        WHILE @@FETCH_STATUS = 0
        BEGIN

            /*-- 挿入： 社員番号 --*/
            SELECT TOP 1
                @wv_henkan = 摘要
            FROM #TBL_ZVMTCODECV_042
            WHERE 管理コード = @wv_shain_no
            ORDER BY 管理コード DESC;

            IF (@wv_henkan IS NULL)
            BEGIN
                SET @wv_i_shain_no = @wv_shain_no;
            END;
            ELSE
            BEGIN
                SET @wv_i_shain_no = CAST(@wv_henkan AS VARCHAR(9));
            END;

            /*-- 挿入： 姓 --*/
            SELECT TOP 1
                @wv_henkan = 摘要
            FROM #TBL_ZVMTCODECV_014
            WHERE 管理コード = @wv_shain_no
            ORDER BY 管理コード DESC;

            IF (@wv_henkan IS NULL)
            BEGIN
                SET @wv_i_sei = @wv_sei;
            END;
            ELSE
            BEGIN
                SET @wv_i_sei = CAST(@wv_henkan AS VARCHAR(30));
            END;

            /*-- 挿入： 名 --*/
            SELECT TOP 1
                @wv_henkan = 摘要
            FROM #TBL_ZVMTCODECV_015
            WHERE 管理コード = @wv_shain_no
            ORDER BY 管理コード DESC;

            IF (@wv_henkan IS NULL)
            BEGIN
                SET @wv_i_mei = @wv_mei;
            END;
            ELSE
            BEGIN
                SET @wv_i_mei = CAST(@wv_henkan AS VARCHAR(30));
            END;

            /*-- 挿入： 氏名 --*/
            IF (DATALENGTH(@wv_i_sei + @wv_i_mei) > 20)
            BEGIN
                SET @wv_i_sei_mei = CONCAT(@wv_i_sei, @wv_i_mei);
            END;
            ELSE
            BEGIN
                SET @wv_i_sei_mei = CONCAT(@wv_i_sei, '　', @wv_i_mei);
            END;

            /*-- 挿入： 実施年度 --*/
            SET @wv_i_jisshi_nendo = LEFT(@wv_koka_nendo, 4);

            /*-- 挿入： 決定賞与(成果)評定 --*/
            SET @wv_i_kettei_shoyo_seika = CAST(@wv_sogo_hyoka_2 AS VARCHAR(3));
            IF (@wv_i_kettei_shoyo_seika IS NULL)
            BEGIN
                SET @wv_i_kettei_shoyo_seika = CAST(@wv_sogo_hyoka_3 AS VARCHAR(3));
            END;

            IF (@wv_i_kettei_shoyo_seika IS NULL)
            BEGIN
                SET @wc_message_level = 'W';
                SET @wv_message = CONCAT('コード値に変換失敗　社員番号：[', @wv_shain_no,
                    ']　出力項目名：決定賞与(成果)評定　算出に使用した値：[', @wv_sogo_hyoka_2, ',', @wv_sogo_hyoka_3, ']');
                EXEC dbo.ZVTTLOG_MAIN
                        @wv_program_name,
                        @wc_message_level,
                        @wv_message;
            END;

            /*-- 挿入： 決定行動評定 --*/
            SET @wv_i_kettei_kodo = CAST(@wv_sogo_hyoka_1 AS VARCHAR(3));

            /*-- 挿入： 社員区分略称 --*/
            SELECT TOP 1
                @wv_i_tokyu_meisho = 等級名称
            FROM [SJMTTOKYU]
            WHERE 等級コード = @wv_shokumu_tokyu_code
                AND 適用開始日 <= @wd_koka_kijunbi
                AND 適用終了日 >= @wd_koka_kijunbi
            ORDER BY 適用開始日 DESC;

            SELECT TOP 1
                @wv_henkan = 摘要
            FROM #TBL_ZVMTCODECV_044
            WHERE テキスト５ = @wv_i_tokyu_meisho
            ORDER BY 管理コード DESC;

            IF (@wv_henkan IS NULL)
            BEGIN
                SET @wv_i_shain_kbn_ryakusho = CAST(@wv_i_tokyu_meisho AS VARCHAR(18));
            END;
            ELSE
            BEGIN
                SET @wv_i_shain_kbn_ryakusho = CAST(@wv_henkan AS VARCHAR(18));
            END;

            IF (@wv_i_shain_kbn_ryakusho IS NULL)
            BEGIN
                SET @wc_message_level = 'W';
                SET @wv_message = CONCAT('コード値に変換失敗　社員番号：[', @wv_shain_no,
                    ']　出力項目名：[社員区分略称]　算出に使用した値：[', @wv_i_shain_kbn_ryakusho, ']');
                EXEC dbo.ZVTTLOG_MAIN
                        @wv_program_name,
                        @wc_message_level,
                        @wv_message;
            END;

            /*-- 挿入： 役割区分略称 --*/
            SELECT TOP 1
                @wv_i_tokyu_meisho = 等級名称
            FROM [SJMTTOKYU]
            WHERE 等級コード = @wv_shokuno_tokyu_code
                AND 適用開始日 <= @wd_koka_kijunbi
                AND 適用終了日 >= @wd_koka_kijunbi
            ORDER BY 適用開始日 DESC;

            SELECT TOP 1
                @wv_henkan = 摘要
            FROM #TBL_ZVMTCODECV_046
            WHERE テキスト５ = @wv_i_tokyu_meisho
            ORDER BY 管理コード DESC;