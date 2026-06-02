VAR b_fecha VARCHAR2(6);

EXEC :b_fecha := TO_CHAR(sysdate, 'MMYYYY')

DECLARE
    v_fecha    DATE := TO_DATE(:b_fecha, 'MMYYYY');
    v_cont NUMBER := 0;
BEGIN
    DBMS_OUTPUT.put_line('PROCESANDO CLIENTES...');
    FOR i IN (
    SELECT 
        c.id_cli,
        c.numrun_cli,
        c.appaterno_cli || ' ' || c.apmaterno_cli || ' ' || c.pnombre_cli  AS cliente,
        FLOOR(MONTHS_BETWEEN(SYSDATE, c.fecha_nac_cli)/12)                 AS edad,
        CASE 
            WHEN c.renta > 800000 AND c.id_comuna NOT IN (80, 84, 85) THEN c.renta * 0.03
            WHEN c.id_tipo_cli IN ('B', 'D') THEN (FLOOR(MONTHS_BETWEEN(SYSDATE, c.fecha_nac_cli)/12)*30)
            ELSE FLOOR((c.renta * te.porcentaje)/100)
        END                                                                 AS puntaje,
        LOWER(c.appaterno_cli)||FLOOR(MONTHS_BETWEEN(SYSDATE, c.fecha_nac_cli)/12)||'*'||SUBSTR(c.pnombre_cli,1,1)||EXTRACT(DAY FROM c.fecha_nac_cli)||EXTRACT(MONTH FROM v_fecha)||'@LogiCarg.cl' AS correo
    FROM cliente c
    LEFT JOIN tramo_edad te ON FLOOR(MONTHS_BETWEEN(SYSDATE, c.fecha_nac_cli)/12) BETWEEN te.tramo_inf AND te.tramo_sup
    AND te.anno_vig = EXTRACT(YEAR FROM SYSDATE)
    ORDER BY c.id_cli)
    LOOP
        INSERT INTO detalle_de_clientes (idc, rut, cliente, edad, puntaje, correo_corp, periodo)
        VALUES (i.id_cli, i.numrun_cli, i.cliente, i.edad, i.puntaje, i.correo, v_fecha);
        v_cont := v_cont + 1;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.put_line('Proceso Finalizado Correctamente');
    DBMS_OUTPUT.put_line('Se procesaron: ' || v_cont || ' cuentas');
END;