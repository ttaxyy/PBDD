-- Caso 1 --

/* ==========================================
                 VARIABLES BIND
   ========================================== */
--Fecha del proceso por calcular en formato 'MMYYYY'
VAR b_fecha VARCHAR2(6);
--EXEC :b_fecha := TO_CHAR(sysdate, 'MMYYYY');
EXEC :b_fecha := '062021';
--Fecha de prueba: Junio 2021

--Valor límite del monto de asignación que se paga a los profesionales
VAR b_limite NUMBER;
EXEC :b_limite := 250000;
---Monto de prueba: $250.000

DECLARE
    /* ==========================================
                     VARIABLES ESCALARES
       ========================================== */
    v_mes_ref    NUMBER := EXTRACT(MONTH FROM TO_DATE(:b_fecha, 'MMYYYY'));
    v_anio_ref   NUMBER := EXTRACT(YEAR  FROM TO_DATE(:b_fecha, 'MMYYYY'));
    
    ---Variables para detalle
    v_num_asesorias                 NUMBER := 0;
    v_hnrarios                      NUMBER := 0;
    v_asgn_extra                    NUMBER := 0;
    v_asgn_tpcontrato               NUMBER := 0;
    v_asgn_profesion                NUMBER := 0;
    v_total_asgn                    NUMBER := 0;
    
    ---Variables para resumen
    v_total_asesorias               NUMBER := 0;
    v_total_hnrarios                NUMBER := 0;
    v_total_movil_extra             NUMBER := 0;
    v_total_asgn_tipocont           NUMBER := 0;
    v_total_asgn_prof               NUMBER := 0;
    v_res_total_asgn                NUMBER := 0;

    ---Excepción definida por el usuario
    excepcion_limite                EXCEPTION;
    
    /* ==========================================
                        REGISTRO
       ========================================== */
    
    ---Crea registro con las variables de las tablas existentes.
    reg_detalle           detalle_asignacion_mes%ROWTYPE;
    reg_resumen           resumen_mes_profesion%ROWTYPE;

    /* ==========================================
                        VARRAY
       ========================================== */
    
    ---Porcentaje de asignación de movilización extra---
    TYPE tp_porc_varray IS VARRAY(5) OF NUMBER;
    
    ---Variable del tipo tp_porc_varray
    varray_porcentaje tp_porc_varray;
    
    /* ==========================================
                CURSORES SIN PARÁMETRO
       ========================================== */
    
    --Obtiene datos básicos + requeridos para cálculos
    CURSOR cur_datos IS 
        SELECT 
            p.numrun_prof,
            p.appaterno || ' ' || p.nombre AS NOMBRE,
            prof.nombre_profesion,
            p.cod_comuna,
            p.cod_tpcontrato,
            p.cod_profesion,
            p.sueldo
        FROM profesional p
        LEFT JOIN profesion prof ON p.cod_profesion = prof.cod_profesion
        ORDER BY p.appaterno || ' ' || p.nombre;
        
    ---Obtiene porcentaje de incentivo por tipo de contrato---
    CURSOR cur_porc_tpcontrato IS
        SELECT cod_tpcontrato, incentivo
        FROM tipo_contrato;
        
    ---Obtiene porcentaje de asignación por profesión---
    CURSOR cur_porc_profesion IS
        SELECT cod_profesion, asignacion
        FROM porcentaje_profesion;
        
    ---Obtiene profesiones (ordenadas)---
    CURSOR cur_profesion IS
        SELECT DISTINCT
            p.cod_profesion,
            prof.nombre_profesion
        FROM profesional p
        LEFT JOIN profesion prof ON p.cod_profesion = prof.cod_profesion
        ORDER BY prof.nombre_profesion ASC;
        
    /* ==========================================
                CURSOR CON PARÁMETRO
       ========================================== */
        
    CURSOR cur_asignaciones(p_prof_numrun NUMBER) IS
        SELECT 
            p.numrun_prof,
            COUNT(a.numrun_prof) AS NUM_ASES,
            SUM(a.honorario) AS HONORARIOS
        FROM profesional p
        JOIN asesoria a ON p.numrun_prof = a.numrun_prof
        WHERE EXTRACT(YEAR  FROM a.inicio_asesoria) = v_anio_ref
        AND EXTRACT(MONTH FROM a.inicio_asesoria) = v_mes_ref
        AND p.numrun_prof = p_prof_numrun
        GROUP BY p.numrun_prof;
        
BEGIN
    ---Se truncan las tablas en tiempo de ejecución ---
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ASIGNACION_MES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_MES_PROFESION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';
    
    ---Se elimina y vuelve a crear secuencia para manejar ID de errores
    EXECUTE IMMEDIATE('DROP SEQUENCE SQ_ERRORES');
    EXECUTE IMMEDIATE('CREATE SEQUENCE SQ_ERRORES');

    ---Asignarle valores a VARRAY---
    varray_porcentaje := tp_porc_varray(2, 4, 5, 7, 9);
    
    FOR prof_res IN cur_profesion LOOP
        ---Se reinician valores.---
        v_total_asesorias           := 0;
        v_total_hnrarios            := 0;
        v_total_movil_extra         := 0;
        v_total_asgn_tipocont       := 0;
        v_total_asgn_prof           := 0;
        v_res_total_asgn            := 0;
    
        FOR profesional IN cur_datos LOOP
            ---Se reinician valores.---
            v_num_asesorias         := 0;
            v_hnrarios              := 0;
            v_asgn_extra            := 0;
            v_asgn_tpcontrato       := 0;
            v_asgn_profesion        := 0;
            
            --Recorrido de datos por profesión---
            IF profesional.cod_profesion = prof_res.cod_profesion THEN
            
                ---Asigna valor a variable desde el cursor 
                FOR asignacion IN cur_asignaciones(profesional.numrun_prof) LOOP
                    ---TODO: Manejar errores en caso de que no haya asesoría
                    v_num_asesorias := asignacion.num_ases;
                    v_hnrarios      := asignacion.honorarios;
                END LOOP;
                
                IF v_num_asesorias > 0 THEN  ---Por ahora, para mostrar solo los que tienen asesorías
                
                    ---Asignación por movilidad extra---
                        --- Comuna = Santiago ---
                    IF profesional.cod_comuna = 82 AND v_hnrarios < 350000 THEN
                        v_asgn_extra := ROUND(varray_porcentaje(1) * 0.01 * v_hnrarios);
                        
                        --- Comuna = Ñuñoa ---
                    ELSIF profesional.cod_comuna = 83 THEN
                        v_asgn_extra := ROUND(varray_porcentaje(2) * 0.01 * v_hnrarios);
                        
                        --- Comuna = La Reina ---
                    ELSIF profesional.cod_comuna = 85 AND v_hnrarios < 400000 THEN
                        v_asgn_extra := ROUND(varray_porcentaje(3) * 0.01 * v_hnrarios);
                        
                        --- Comuna = La Florida ---
                    ELSIF profesional.cod_comuna = 86 AND v_hnrarios < 800000 THEN
                        v_asgn_extra := ROUND(varray_porcentaje(4) * 0.01 * v_hnrarios);
                        
                        --- Comuna = Macul ---
                    ELSIF profesional.cod_comuna = 89 AND v_hnrarios < 680000 THEN
                        v_asgn_extra := ROUND(varray_porcentaje(5) * 0.01 * v_hnrarios);
                    END IF;
                    
                    ---Asignación por tipo de contrato (calculado respecto a la suma de honorarios)---
                    FOR tp_contrato IN cur_porc_tpcontrato LOOP
                        IF profesional.cod_tpcontrato = tp_contrato.cod_tpcontrato THEN
                            v_asgn_tpcontrato := ROUND(v_hnrarios * 0.01 * tp_contrato.incentivo);
                        END IF;
                    END LOOP;
                    
                    ---Asignación por profesión (calculada en base a sueldo)---
                    FOR profesion IN cur_porc_profesion LOOP
                        IF profesional.cod_profesion = profesion.cod_profesion THEN
                            v_asgn_profesion := ROUND(profesional.sueldo * 0.01 * profesion.asignacion);
                        END IF;
                    END LOOP;
                    
                    ---Manejo de total de asignaciones---
                    BEGIN
                    IF v_asgn_extra + v_asgn_tpcontrato + v_asgn_profesion < :b_limite THEN
                        v_total_asgn            := v_asgn_extra + v_asgn_tpcontrato + v_asgn_profesion;
                    ELSE   
                        v_total_asgn            := :b_limite;
                        RAISE excepcion_limite;
                    END IF;
                    
                    /* ==========================================
                                MANEJO DE ERROR LÍMITE
                       ========================================== */
                    EXCEPTION
                        WHEN excepcion_limite THEN
                            --- Registrar el error pero continuar con el proceso ---
                            INSERT INTO ERRORES_PROCESO VALUES (SQ_ERRORES.NEXTVAL, 'TOPE_SUPERADO',
                                'Se reemplazó el monto total de las asignaciones calculadas de ' || (v_asgn_extra + v_asgn_tpcontrato + v_asgn_profesion) || ' por el monto límite de ' || :b_limite || ' para el run Nro. ' || profesional.numrun_prof
                            );
                    END;
                    
                    ---Asignar datos a registro---
                    reg_detalle.mes_proceso                 := v_mes_ref;
                    reg_detalle.anno_proceso                := v_anio_ref;
                    reg_detalle.run_profesional             := profesional.numrun_prof;
                    reg_detalle.nombre_profesional          := profesional.nombre;
                    reg_detalle.profesion                   := profesional.nombre_profesion;
                    reg_detalle.nro_asesorias               := v_num_asesorias;
                    reg_detalle.monto_honorarios            := v_hnrarios;
                    reg_detalle.monto_movil_extra           := v_asgn_extra;
                    reg_detalle.monto_asig_tipocont         := v_asgn_tpcontrato;
                    reg_detalle.monto_asig_profesion        := v_asgn_profesion;
                    reg_detalle.monto_total_asignaciones    := v_total_asgn;
                    
                    INSERT INTO detalle_asignacion_mes VALUES reg_detalle;
                    
                    v_total_asesorias           := v_total_asesorias + v_num_asesorias;
                    v_total_hnrarios            := v_total_hnrarios + v_hnrarios;
                    v_total_movil_extra         := v_total_movil_extra + v_asgn_extra;
                    v_total_asgn_tipocont       := v_total_asgn_tipocont + v_asgn_tpcontrato;
                    v_total_asgn_prof           := v_total_asgn_prof + v_asgn_profesion;
                    v_res_total_asgn            := v_res_total_asgn + v_total_asgn;
                END IF;
            END IF;
        END LOOP;
        
        reg_resumen.anno_mes_proceso            := TO_CHAR(TO_DATE(:b_fecha, 'MMYYYY'),'YYYYMM');
        reg_resumen.profesion                   := prof_res.nombre_profesion;
        reg_resumen.total_asesorias             := v_total_asesorias;
        reg_resumen.monto_total_honorarios      := v_total_hnrarios;
        reg_resumen.monto_total_movil_extra     := v_total_movil_extra;
        reg_resumen.monto_total_asig_tipocont   := v_total_asgn_tipocont;
        reg_resumen.monto_total_asig_prof       := v_total_asgn_prof;
        reg_resumen.monto_total_asignaciones    := v_res_total_asgn;
        
        INSERT INTO resumen_mes_profesion VALUES reg_resumen;
            
    END LOOP;
    
    COMMIT;
    
EXCEPTION
    /* WHEN NO_DATA_FOUND THEN
        INSERT INTO ERRORES_PROCESO VALUES (SQ_ERRORES.NEXTVAL, SQLERRM,
         'Error al obtener porcentaje de asignación para el rut Nro. ' || profesional.numrun_prof
        ); */
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
END;
/

SELECT * FROM DETALLE_ASIGNACION_MES;

SELECT * FROM RESUMEN_MES_PROFESION;

SELECT * FROM ERRORES_PROCESO;