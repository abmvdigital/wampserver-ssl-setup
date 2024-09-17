@echo off
:: Limpa a tela
cls

:: Habilita a expansão atrasada de variáveis
setlocal enabledelayedexpansion 

:: Define variáveis comuns de instalação
set "diretorios_instalacao=C:\wamp64 C:\wamp D:\wamp64 D:\wamp"
set "diretorio_wamp="
set "diretorio_apache="

:: Corrige a exibição de caracteres especiais utf-8 no prompt de comando
chcp 65001 > nul

:: Verifica se o script está sendo executado como administrador
if not "%__APPDIR__%cacls.exe"=="%SYSTEMROOT%\system32\cacls.exe" (
    echo Por favor, execute este script como administrador.
    pause
    exit /b
)

:executarScript

:: Verifica diretórios de instalação do WAMP
call :verificar_diretorios
if not defined diretorio_wamp (
    echo Não foi encontrado o diretório da instalação do WAMP.
    echo Exemplo: "C:\wamp64"
    set /p "diretorio_wamp=Informe o diretório de instalação do WAMP: "
    if not exist "!diretorio_wamp!" (
        echo O diretório "!diretorio_wamp!" não é válido.
        pause
        cls
        goto :executarScript
    )
)
echo Diretório da instalação do WAMP encontrado: %diretorio_wamp%

:: Busca o diretório de instalação do Apache
call :verificar_apache
if not defined diretorio_apache (
    echo Não foi encontrado o diretório da instalação do Apache.
    echo Verifique se a instalação WampServer está correta e tente novamente.
    exit /b
) else (
    echo Diretório da instalação do Apache encontrado: %diretorio_apache%
    call :gerar_certificado
    call :configurar_apache
    echo Certificado instalado com sucesso.
)

:: Abre a página do projeto no navegador
start https://github.com/abmvdigital/wampserver-ssl-setup

exit /b

:verificar_diretorios
for %%d in (%diretorios_instalacao%) do (
    if exist "%%d" (
        set "diretorio_wamp=%%d"
        exit /b
    )
)

:: Se não encontrou, procura no registro do Windows
for /f "tokens=3*" %%a in ('reg query "HKLM\Software\WAMPServer" /v InstallDir 2^>nul') do (
    if exist "%%b" (
        set "diretorio_wamp=%%b"
        exit /b
    )
)
exit /b

:verificar_apache
for /d %%a in ("%diretorio_wamp%\bin\apache\apache*") do (
    set "diretorio_apache=%%~fa"
    exit /b
)
exit /b

:gerar_certificado
cd /d "%diretorio_apache%\bin"

:: Solicita ao usuário a senha (opcional)
set /p "senha_certificado=Digite a senha para o certificado (deixe em branco para padrão): "
if "%senha_certificado%"=="" set "senha_certificado=sua_senha"

:: Solicita ao usuário informações do certificado (opcional)
set "default_subj=/C=BR/ST=Minas Gerais/L=Minas Gerais/O=localhost/OU=localhost/CN=localhost"
set /p "informacoes_certificado=Digite as informações do certificado (deixe em branco para padrão): "
if "%informacoes_certificado%"=="" set "informacoes_certificado=%default_subj%"

:: Cria o arquivo de configuração do certificado
(
echo authorityKeyIdentifier=keyid,issuer
echo basicConstraints=CA:FALSE
echo keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
echo subjectAltName = @alt_names
echo [alt_names]
echo DNS.1 = localhost
) > domains.ext

:: Cria a requisição do certificado
openssl req -new -out server.csr -passout pass:%senha_certificado% -subj "%informacoes_certificado%"

:: Gera a chave privada
openssl rsa -in privkey.pem -out server.key -passin pass:%senha_certificado%

:: Gera o certificado
openssl x509 -in server.csr -out server.crt -req -signkey server.key -days 3650 -sha256 -extfile domains.ext

:: Remove arquivos desnecessários
del privkey.pem server.csr domains.ext

:: Move os arquivos para o diretório de configuração do Apache
move /y server.crt "%diretorio_apache%\conf\server.crt"
move /y server.key "%diretorio_apache%\conf\server.key"

exit /b

:configurar_apache
:: Configura o arquivo httpd.conf
set "arquivo_httpd_conf=%diretorio_apache%\conf\httpd.conf"
powershell -Command "(Get-Content '%arquivo_httpd_conf%') -replace '#LoadModule ssl_module modules/mod_ssl.so', 'LoadModule ssl_module modules/mod_ssl.so' | Set-Content '%arquivo_httpd_conf%'"
powershell -Command "(Get-Content '%arquivo_httpd_conf%') -replace '#Include conf/extra/httpd-ssl.conf', 'Include conf/extra/httpd-ssl.conf' | Set-Content '%arquivo_httpd_conf%'"
powershell -Command "(Get-Content '%arquivo_httpd_conf%') -replace '#LoadModule socache_shmcb_module modules/mod_socache_shmcb.so', 'LoadModule socache_shmcb_module modules/mod_socache_shmcb.so' | Set-Content '%arquivo_httpd_conf%'"

:: Configura o arquivo httpd-ssl.conf
set "arquivo_httpd_ssl_conf=%diretorio_apache%\conf\extra\httpd-ssl.conf"
powershell -Command "(Get-Content '%arquivo_httpd_ssl_conf%') -replace 'DocumentRoot.*', 'DocumentRoot \"${INSTALL_DIR}/www\"' | Set-Content '%arquivo_httpd_ssl_conf%'"
powershell -Command "(Get-Content '%arquivo_httpd_ssl_conf%') -replace 'ServerName.*', 'ServerName localhost:443' | Set-Content '%arquivo_httpd_ssl_conf%'"

:: Instala o certificado
set "caminho_certificado=%diretorio_apache%\conf\server.crt"
certutil -addstore -user "Root" "%caminho_certificado%"

exit /b
