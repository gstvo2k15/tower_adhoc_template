# Checks Middleware -- SSL Handshake Failure

## 2. Certificar resolución DNS

``` bash
getent hosts secweb-stest3.dev.echonet
```

``` bash
nslookup secweb-stest3.dev.echonet
```

Según las evidencias actuales, debería acabar resolviendo
aproximadamente así:

``` text
secweb-stest3.dev.echonet
 -> vs-avi-fido-secwebstest3avi-dev.xmp.net.intra
 -> 10.118.107.252
```

Esto también aporta evidencia de que aparentemente existe un AVI/VIP
involucrado.

## 3. Certificar conectividad TCP/443

``` bash
nc -vz secweb-stest3.dev.echonet 443
```

Si `nc` no está disponible:

``` bash
timeout 5 bash -c '</dev/tcp/secweb-stest3.dev.echonet/443' \
&& echo "TCP 443 OK" || echo "TCP 443 FAIL"
```

Si devuelve OK:

``` text
TCP connection = OK
TLS handshake  = siguiente nivel
```

Esto descarta un bloqueo básico de TCP/443, pero no una inspección o
política de firewall sobre TLS.

## 4. Probar TLS sin Java y sin Tomcat

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2
```

Para guardar toda la salida:

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2 </dev/null 2>&1 | tee /tmp/secweb_tls12.txt
```

Si también aparece `alert handshake failure`, el problema queda
reproducido sin Tomcat ni Java.

## 5. Probar directamente contra la IP manteniendo SNI

``` bash
openssl s_client \
-connect 10.118.107.252:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2 </dev/null
```

Esta prueba elimina DNS de la conexión, pero mantiene el hostname TLS
correcto mediante SNI.

## 6. Obtener la IP origen utilizada

``` bash
ip route get 10.118.107.252
```

El dato importante es el campo `src`. Network/Security puede buscar el
flujo:

``` text
SRC  = <source IP>
DST  = 10.118.107.252
PORT = 443
```

## 7. Correlacionar con la evidencia Java

La JVM muestra:

``` text
ClientHello
supported_versions: [TLSv1.2]
server_name: secweb-stest3.dev.echonet
WRITE: TLSv1.2 handshake
READ: TLSv1.2 alert
Received fatal alert: handshake_failure
```

Si `openssl s_client` reproduce el mismo fallo, Tomcat/JDK deja de ser
necesario para reproducir el incidente.

## 8. Probar cipher suites concretas con TLS 1.2

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2 \
-cipher 'ECDHE-RSA-AES128-GCM-SHA256'
```

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2 \
-cipher 'ECDHE-RSA-AES256-GCM-SHA384'
```

Prueba adicional:

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2 \
-cipher 'AES128-GCM-SHA256'
```

Si funciona, OpenSSL mostrará un cipher negociado. Si es rechazado,
normalmente aparecerá `alert handshake failure` y no habrá cipher
negociado.

## 9. Comparar TLS 1.2 y TLS 1.3

TLS 1.2:

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2
```

Si OpenSSL soporta TLS 1.3:

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_3
```

Registrar:

``` text
TLS 1.2 -> OK / FAIL
TLS 1.3 -> OK / FAIL
```

## 10. Comprobar restricciones TLS del JDK

Sólo recoger la configuración; no modificarla:

``` bash
grep -A5 '^jdk.tls.disabledAlgorithms' \
$JAVA_HOME/conf/security/java.security
```

``` bash
grep -A5 '^jdk.certpath.disabledAlgorithms' \
$JAVA_HOME/conf/security/java.security
```

No deshabilitar `jdk.tls.disabledAlgorithms` ni habilitar algoritmos
inseguros como solución.

## 11. Alcance Tomcat/JDK

La comunicación problemática es una llamada HTTPS saliente mediante
Java/JSSE/RestTemplate.

No se debe modificar el TLS de `server.xml` de Tomcat para este
problema. Los conectores TLS de `server.xml` corresponden principalmente
a conexiones HTTPS entrantes donde Tomcat actúa como servidor.

``` text
Aplicación / RestTemplate
        |
        v
Java JSSE (cliente TLS)
        |
        v
Red / Security / Proxy / AVI
        |
        v
secweb-stest3.dev.echonet
```

## 12. Criterio para escalar fuera de Middleware

Si:

``` bash
openssl s_client \
-connect secweb-stest3.dev.echonet:443 \
-servername secweb-stest3.dev.echonet \
-tls1_2
```

también devuelve `handshake failure`, el fallo queda reproducido sin
utilizar Tomcat, JDK, cacerts de Java, RestTemplate ni JSSE.

En ese caso, no realizar más cambios en Tomcat/JDK hasta que el
propietario de la infraestructura revise:

-   Firewall.
-   Proxy.
-   TLS Inspection.
-   AVI / Load Balancer.
-   Políticas dependientes de la IP origen.
-   Restricciones de versión TLS.
-   Restricciones de cipher suites.

### Información a proporcionar a Network/Security

``` text
Source IP: <resultado de ip route get>
Destination IP: 10.118.107.252
Destination port: 443
SNI: secweb-stest3.dev.echonet
Protocol tested: TLSv1.2

Ciphers tested:
ECDHE-RSA-AES128-GCM-SHA256
ECDHE-RSA-AES256-GCM-SHA384
AES128-GCM-SHA256

Result:
<OK / handshake_failure>
```

> Importante: si `openssl s_client` funciona correctamente pero Java
> falla, no se puede concluir que el problema esté fuera de JDK/JSSE. En
> ese caso hay que continuar el diagnóstico en Java.
