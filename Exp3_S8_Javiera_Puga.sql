-------- Caso 1 --------

/* ==========================================
                  PACKAGE
   ========================================== */
 
------- Encabezado Package -------
CREATE OR REPLACE PACKAGE PKG_GESTION_PROMEDIO
IS
    --- Variables públicas ---
    v_monto_promedio    NUMBER := 0;
    v_annio_proceso     NUMBER;
 
    --------- Función ---------
    -- Recibe el año de proceso y calcula el promedio de ventas del año ANTERIOR
    FUNCTION F_OBTENER_MONTO_PROMEDIO
        (p_annio IN NUMBER)
    RETURN NUMBER;
 
    ------ Procedimiento ------
    PROCEDURE P_INSERTAR_ERROR
        (p_rutina_error  IN VARCHAR2,
         p_descrip_error IN VARCHAR2,
         p_descrip_user  IN VARCHAR2);
 
END PKG_GESTION_PROMEDIO;
/
    
------- Cuerpo Package -------
CREATE OR REPLACE PACKAGE BODY PKG_GESTION_PROMEDIO
IS
 
    --- Función cumple regla de negocio A ---
    FUNCTION F_OBTENER_MONTO_PROMEDIO
        (p_annio IN NUMBER)
        RETURN NUMBER
    IS
        v_monto_promedio NUMBER;
    BEGIN
        SELECT ROUND(AVG(total_boleta))
        INTO v_monto_promedio
        FROM (
            SELECT db.nro_boleta,
            AVG(db.valor_total) AS total_boleta
            FROM DETALLE_BOLETA db
            LEFT JOIN BOLETA b ON db.nro_boleta = b.nro_boleta
            WHERE EXTRACT(YEAR FROM b.fecha) = p_annio - 1 ---Año anterior al que se está procesando
            GROUP BY db.nro_boleta
        );
        
        DBMS_OUTPUT.PUT_LINE('Promedio: ' || v_monto_promedio);
        RETURN v_monto_promedio;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN 0;
    END F_OBTENER_MONTO_PROMEDIO;
 
 
    PROCEDURE P_INSERTAR_ERROR
        (p_rutina_error  IN VARCHAR2,
         p_descrip_error IN VARCHAR2,
         p_descrip_user  IN VARCHAR2)
    IS
    BEGIN
        INSERT INTO ERROR_CALC (correl_error, rutina_error, descrip_error, descrip_user)
        VALUES (SEQ_ERROR.NEXTVAL, p_rutina_error, p_descrip_error, p_descrip_user);
    END P_INSERTAR_ERROR;
 
END PKG_GESTION_PROMEDIO;
/

   
/* ==========================================
            FUNCIONES ALMACENADAS
   ========================================== */
 
-------- Función 1 --------
----- Retorna porcentaje de asignación por antiguedad -----
 
CREATE OR REPLACE FUNCTION FN_PORC_ANTIGUEDAD
    (p_rut IN VARCHAR2)
    RETURN NUMBER
IS
    v_annios NUMBER;
    v_porc NUMBER;
BEGIN
    SELECT FLOOR(MONTHS_BETWEEN(SYSDATE, e.fecha_contrato)/12)
    INTO v_annios
    FROM EMPLEADO e
    WHERE e.run_empleado = p_rut;
 
    SELECT PORC_ANTIGUEDAD
    INTO v_porc
    FROM PCT_ANTIGUEDAD
    WHERE v_annios BETWEEN ANNOS_ANTIGUEDAD_INF AND ANNOS_ANTIGUEDAD_SUP;
 
    RETURN v_porc;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
END FN_PORC_ANTIGUEDAD;
/

-------- Función 2 --------
----- Retorna porcentaje de asignación según su nivel de estudios -----
 
CREATE OR REPLACE FUNCTION FN_PORC_ESTUDIOS
    (p_rut IN VARCHAR2)
    RETURN NUMBER
IS
    v_porc NUMBER;
BEGIN
    SELECT
    ne.porc_escolaridad
    INTO v_porc
    FROM PCT_NIVEL_ESTUDIOS ne
    LEFT JOIN EMPLEADO e ON ne.cod_escolaridad = e.cod_escolaridad
    WHERE e.run_empleado = p_rut
    AND e.cod_salud = 1; --Si es fonasa
 
    RETURN v_porc;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
END FN_PORC_ESTUDIOS;
/

-------- Función 3 --------
----- Determina si cumple con la condición para recibir la asignación por antiguedad -----
 
CREATE OR REPLACE FUNCTION FN_RECIBE_ASIGNACION
    (p_rut IN VARCHAR2,
     p_promedio IN NUMBER)
    RETURN NUMBER
IS
    v_monto_total NUMBER;
    v_porc_ventas NUMBER;
    v_recibe_asignacion NUMBER(1);
BEGIN
    SELECT SUM(b.monto_total_boleta)
    INTO v_monto_total
    FROM BOLETA b
    LEFT JOIN EMPLEADO e ON b.run_empleado = e.run_empleado
    WHERE EXTRACT(YEAR FROM fecha) = pkg_gestion_promedio.v_annio_proceso
    AND b.run_empleado = p_rut
    AND e.tipo_empleado = 5 ---Si el tipo = empleado
    GROUP BY b.run_empleado;
 
    v_porc_ventas := v_monto_total * 0.07;
    DBMS_OUTPUT.PUT_LINE('7% de las ventas totales : ' || v_porc_ventas);
    
    IF (v_porc_ventas > p_promedio) THEN
        v_recibe_asignacion := 1;
    ELSE
        v_recibe_asignacion := 0;
    END IF;
 
    RETURN v_recibe_asignacion;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 0;
END FN_RECIBE_ASIGNACION;
/

/* ==========================================
                PROCEDIMIENTO
   ========================================== */
 
CREATE OR REPLACE PROCEDURE SP_CALCULO_ASIGNACIONES_VENDEDORES
    (p_fecha_proceso DATE)
IS
    v_porc_antiguedad NUMBER;
    v_asig_antiguedad NUMBER;
    v_asig_estudio    NUMBER;
    v_promedio        NUMBER;
 
     CURSOR cur_datos_empleado IS
        SELECT e.run_empleado,
        INITCAP(e.nombre || ' ' || e.paterno) AS nombre,
        e.sueldo_base
        FROM EMPLEADO e;
BEGIN
    --- Se truncan las tablas para poder reejecutar el proceso las veces que sea necesario
    EXECUTE IMMEDIATE 'TRUNCATE TABLE LIQUIDACION_EMPLEADO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_CALC';
 
    pkg_gestion_promedio.v_annio_proceso := EXTRACT(YEAR FROM p_fecha_proceso);
    v_promedio := PKG_GESTION_PROMEDIO.F_OBTENER_MONTO_PROMEDIO(pkg_gestion_promedio.v_annio_proceso);
    
 
    FOR empleado IN cur_datos_empleado LOOP
        DBMS_OUTPUT.PUT_LINE('Empleado: ' || empleado.nombre);
 
        --- Cálculo de asignación por antigüedad ---
        BEGIN
            IF (FN_RECIBE_ASIGNACION(empleado.run_empleado, v_promedio) = 1) THEN
                v_porc_antiguedad := FN_PORC_ANTIGUEDAD(empleado.run_empleado);
                v_asig_antiguedad := v_porc_antiguedad * 0.01 * empleado.sueldo_base;
                DBMS_OUTPUT.PUT_LINE('Recibe asignación.');
            ELSE
                v_asig_antiguedad := 0;
                DBMS_OUTPUT.PUT_LINE('No recibe asignación.');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_asig_antiguedad := 0;
                PKG_GESTION_PROMEDIO.P_INSERTAR_ERROR(
                    'FN_RECIBE_ASIGNACION / FN_PORC_ANTIGUEDAD',
                    SQLERRM,
                    'Error al calcular asignación por antigüedad para RUT ' || empleado.run_empleado
                );
        END;
 
        --- Cálculo de asignación por escolaridad ---
        BEGIN
            v_asig_estudio := FN_PORC_ESTUDIOS(empleado.run_empleado) * 0.01 * empleado.sueldo_base;
        EXCEPTION
            WHEN OTHERS THEN
                v_asig_estudio := 0;
                PKG_GESTION_PROMEDIO.P_INSERTAR_ERROR(
                    'FN_PORC_ESTUDIOS',
                    SQLERRM,
                    'Error al calcular asignación por escolaridad para RUT ' || empleado.run_empleado
                );
        END;
 
        INSERT INTO LIQUIDACION_EMPLEADO VALUES (
            EXTRACT(MONTH FROM p_fecha_proceso),
            EXTRACT(YEAR FROM p_fecha_proceso),
            empleado.run_empleado,
            empleado.nombre,
            empleado.sueldo_base,
            v_asig_antiguedad,
            v_asig_estudio,
            empleado.sueldo_base + v_asig_antiguedad + v_asig_estudio
        );
 
    END LOOP;
 
END SP_CALCULO_ASIGNACIONES_VENDEDORES;
/

/* ==========================================
                TRIGGER
   ========================================== */
 
/*CREATE OR REPLACE TRIGGER TRG_CONTROL_PRODUCTO
    FOR INSERT OR DELETE OR UPDATE OF valor_unitario ON PRODUCTO
 
BEGIN
 
END TRG_CONTROL_PRODUCTO;
/*/


------EJECUCIÓN-------
EXEC SP_CALCULO_ASIGNACIONES_VENDEDORES(TO_DATE('01-06-2024', 'DD-MM-YYYY'));

SELECT * FROM LIQUIDACION_EMPLEADO;

SELECT * FROM ERROR_CALC;