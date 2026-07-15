grep -RniE '^[[:space:]]*LoadModule[[:space:]]+security2_module' /data/apache_emandate/apache/conf /apps/install/apache/2.4.65/conf 2>/dev/null

grep -RniE 'security2_module|mod_security2\.so|Include(Optional)?' /data/apache_emandate/apache/conf /apps/install/apache/2.4.65/conf 2>/dev/null



# Lo habitual es encontrar algo equivalente a esto en dos archivos:

LoadModule security2_module modules/mod_security2.so

# Por ejemplo:

httpd.conf
conf.modules.d/00-security.conf
conf.d/mod_security.conf
WebAgent.conf


# Debes dejar una sola directiva LoadModule. Los archivos de reglas pueden seguir incluidos; no elimines los Include del OWASP CRS salvo que también estén duplicados.

# Ejemplo correcto:

LoadModule security2_module modules/mod_security2.so

IncludeOptional conf.d/modsecurity/*.conf
IncludeOptional conf.d/owasp-crs/*.conf

# Comprueba también que el mismo archivo no se incluya dos veces:

Include conf/WebAgent.conf
IncludeOptional conf.d/*.conf


```bash 
Si WebAgent.conf ya está dentro de conf.d, ambas líneas pueden provocar una segunda lectura.

Después valida:

/apps/install/apache/2.4.65/bin/httpd \
    -t \
    -f /data/apache_emandate/apache/conf/httpd.conf

Y lista los módulos:

/apps/install/apache/2.4.65/bin/httpd \
    -M \
    -f /data/apache_emandate/apache/conf/httpd.conf |
grep security

El resultado esperado es una sola línea:

security2_module (shared)

El mensaje es un warning, no un fallo de arranque. Apache ignora la segunda carga y continúa. Corrige la duplicidad para evitar configuraciones ambiguas y no uses kill -9 para reinicios normales; usa el script de parada o:

/apps/install/apache/2.4.65/bin/httpd \
    -k graceful \
    -f /data/apache_emandate/apache/conf/httpd.conf
```
