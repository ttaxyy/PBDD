----- EFT -----

/* ==========================================
                 VARIABLES BIND
   ========================================== */
   
--Porcentaje de puntuación extra--
VAR b_porcentaje NUMBER;
EXEC :b_porcentaje := 35;

/* ==========================================
                 SECUENCIA
   ========================================== */
   
--Secuencia tabla error---
DROP SEQUENCE SEQ_ERROR;
CREATE SEQUENCE SEQ_ERROR
    START WITH 1
    INCREMENT BY 1
    NOCACHE;

/* ==========================================
                  PACKAGE
   ========================================== */
   
------- Encabezado Package -------
CREATE OR REPLACE PACKAGE PKG_GESTION_PUNTAJE
IS
    ------ Variable pública ------
    v_puntaje_extra    NUMBER := 0;
 
    --------- Función ---------
    FUNCTION F_OBTENER_PUNTAJE_EXTRA
        (p_run IN NUMBER,
        p_porc IN NUMBER,
        p_puntaje1 IN NUMBER,
        p_puntaje2 IN NUMBER)
    RETURN NUMBER;
    
    -------Proceso manejo errores--------
    PROCEDURE P_INSERTAR_ERROR
        (p_rutina_error  IN VARCHAR2,
         p_descrip_error IN VARCHAR2);
 
END PKG_GESTION_PUNTAJE;
/

------- Cuerpo Package -------
CREATE OR REPLACE PACKAGE BODY PKG_GESTION_PUNTAJE
IS
    --Función 1.3. Cálculo puntaje extra--
    FUNCTION F_OBTENER_PUNTAJE_EXTRA
        (p_run IN NUMBER,
        p_porc IN NUMBER,
        p_puntaje1 IN NUMBER,
        p_puntaje2 IN NUMBER)
        RETURN NUMBER
    IS
        v_establecimientos NUMBER;
        v_horas_semanales NUMBER;
    BEGIN
        ---Obtiene suma horas semanales por rut---
        SELECT SUM(horas_semanales)
        INTO v_horas_semanales
        FROM ANTECEDENTES_LABORALES
        WHERE numrun = p_run
        GROUP BY numrun;

        ---Obtiene número de establecimientos en el que trabaja---
        SELECT COUNT(numrun)
        INTO v_establecimientos
        FROM ANTECEDENTES_LABORALES
        WHERE numrun = p_run
        GROUP BY numrun;
        
        DBMS_OUTPUT.PUT_LINE('Horas: ' || v_horas_semanales);
        DBMS_OUTPUT.PUT_LINE('Establecimientos: ' || v_establecimientos);
        
        ---Cálculo de puntuación extra---
        IF (v_horas_semanales > 30 AND v_establecimientos > 1) THEN
            v_puntaje_extra := ROUND(p_porc * 0.01 * (p_puntaje1 + p_puntaje2));
        ELSE
            v_puntaje_extra := 0;
        END IF;
    
        RETURN v_puntaje_extra;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            PKG_GESTION_PUNTAJE.P_INSERTAR_ERROR('F_OBTENER_PUNTAJE_EXTRA', SQLERRM);
            v_puntaje_extra := 0;
            RETURN 0;
    END F_OBTENER_PUNTAJE_EXTRA;
    
    -------Proceso manejo errores--------
    PROCEDURE P_INSERTAR_ERROR
        (p_rutina_error  IN VARCHAR2,
         p_descrip_error IN VARCHAR2)
    IS
    BEGIN
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL, p_rutina_error, p_descrip_error);
    END P_INSERTAR_ERROR;
 
END PKG_GESTION_PUNTAJE;
/

/* ==========================================
            FUNCIONES ALMACENADAS
   ========================================== */

--Función 1.1. Cálculo puntaje por años de experiencia--
CREATE OR REPLACE FUNCTION FN_PUNTAJE_EXP
    (p_rut IN NUMBER)
    RETURN NUMBER
IS
    v_annios NUMBER;
    v_ptje NUMBER;
BEGIN
    ---Obtiene años desde el contrato más antiguo---
    ---Se usa el mismo año en el que se corre el proceso: Usa SYSDATE---
    SELECT MAX(FLOOR(MONTHS_BETWEEN(SYSDATE, fecha_contrato)/12)) 
    INTO v_annios
    FROM ANTECEDENTES_LABORALES
    WHERE numrun = p_rut
    GROUP BY numrun;
    
    ---Obtiene puntaje basado en años trabajados---
    SELECT PTJE_EXPERIENCIA
    INTO v_ptje
    FROM PTJE_ANNOS_EXPERIENCIA
    WHERE v_annios BETWEEN RANGO_ANNOS_INI AND RANGO_ANNOS_TER;
 
    RETURN v_ptje;
EXCEPTION
    WHEN OTHERS THEN
        PKG_GESTION_PUNTAJE.P_INSERTAR_ERROR('FN_PUNTAJE_EXP', SQLERRM);
        RETURN 0;
END FN_PUNTAJE_EXP;
/

--Función 1.2. Cálculo puntaje asociado al país al que postula--
CREATE OR REPLACE FUNCTION FN_PUNTAJE_PAIS
    (p_rut IN NUMBER)
    RETURN NUMBER
IS
    v_ptje NUMBER;
BEGIN
    ---Obtiene puntaje basado en postulación>programa>institucion relacionada>país---
    SELECT ptje.ptje_pais
    INTO v_ptje
    FROM POSTULACION_PASANTIA_PERFEC post
    JOIN PASANTIA_PERFECCIONAMIENTO pas ON post.cod_programa = pas.cod_programa
    JOIN INSTITUCION inst ON pas.cod_inst = inst.cod_inst
    JOIN PTJE_PAIS_POSTULA ptje ON ptje.cod_pais = inst.cod_pais
    WHERE post.numrun = p_rut;
 
    RETURN v_ptje;
EXCEPTION
    WHEN OTHERS THEN
        PKG_GESTION_PUNTAJE.P_INSERTAR_ERROR('FN_PUNTAJE_PAIS', SQLERRM);
        RETURN 0;
END FN_PUNTAJE_PAIS;
/

/* ==========================================
                PROCEDIMIENTO
   ========================================== */

CREATE OR REPLACE PROCEDURE SP_INFORMACION_POSTULANTE
    (p_porc NUMBER)
IS
    v_puntaje_exp       NUMBER;
    v_puntaje_pais      NUMBER;
    
    ---Cursor para obtener run y nombre completo del postulante---
    CURSOR cur_datos_postulante IS
        SELECT numrun,
        TO_CHAR(numrun, '99G999G999')|| '-' || dvrun AS run_postulante,
        INITCAP(pnombre || ' ' || snombre || ' ' || apaterno || ' ' || amaterno) AS nombre_postulante
        FROM ANTECEDENTES_PERSONALES
        ORDER BY numrun;
BEGIN
    --- Se truncan las tablas para poder reejecutar el proceso las veces que sea necesario
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_PUNTAJE_POSTULACION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_PROCESO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESULTADO_POSTULACION';
    
    FOR postulante IN cur_datos_postulante LOOP
        v_puntaje_exp   := FN_PUNTAJE_EXP(postulante.numrun);
        v_puntaje_pais  := FN_PUNTAJE_PAIS(postulante.numrun);
        
        DBMS_OUTPUT.PUT_LINE('Postulante: ' || postulante.run_postulante);
        DBMS_OUTPUT.PUT_LINE('Ptje Exp: ' || v_puntaje_exp);
        DBMS_OUTPUT.PUT_LINE('Ptje Pais: ' || v_puntaje_pais);
        DBMS_OUTPUT.PUT_LINE('Ptje Extra: ' || PKG_GESTION_PUNTAJE.F_OBTENER_PUNTAJE_EXTRA(postulante.numrun, p_porc, v_puntaje_exp, v_puntaje_pais));
        DBMS_OUTPUT.PUT_LINE('---------------------------');
        
        ---Se ingresan datos a la tabla. Se usa variable pública del package.---
        INSERT INTO DETALLE_PUNTAJE_POSTULACION VALUES (
            postulante.run_postulante,
            postulante.nombre_postulante,
            v_puntaje_exp,
            v_puntaje_pais,
            PKG_GESTION_PUNTAJE.v_puntaje_extra
        );
        
    END LOOP;
 
END SP_INFORMACION_POSTULANTE;
/

/* ==========================================
                   TRIGGER
   ========================================== */

CREATE OR REPLACE TRIGGER TRG_RESULTADO
BEFORE INSERT ON DETALLE_PUNTAJE_POSTULACION
FOR EACH ROW
DECLARE
    v_ptje_final    NUMBER;
    v_resultado     VARCHAR2(20);
BEGIN

    v_ptje_final := :NEW.PTJE_ANNOS_EXP + :NEW.PTJE_PAIS_POSTULA + PKG_GESTION_PUNTAJE.v_puntaje_extra;
    
    IF (v_ptje_final >= 2500) THEN
        v_resultado := 'SELECCIONADO';
    ELSE
        v_resultado := 'NO SELECCIONADO';
    END IF;
    
    INSERT INTO RESULTADO_POSTULACION VALUES (
        :NEW.RUN_POSTULANTE,
        v_ptje_final,
        v_resultado
    );
    
END TRG_RESULTADO;
/

/* ==========================================
                  EJECUCIÓN
   ========================================== */
EXEC SP_INFORMACION_POSTULANTE(:b_porcentaje);

SELECT * FROM DETALLE_PUNTAJE_POSTULACION;

SELECT * FROM ERROR_PROCESO;

SELECT * FROM RESULTADO_POSTULACION;

