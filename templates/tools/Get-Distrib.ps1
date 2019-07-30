function Get-Distrib {
    Param($username, $password, $version, $out_file)

    # Валидация параметров

    Get-Distrib-Validate-Input `
        -username $username `
        -password $password `
        -version $version `
        -out_file $out_file

    # Авторизуемся 
    $session = Get-session -username $username -password $password

    # Получим ссылку на скачивание дистрибутива
    $url = Get-Distrib-link -version $version -session $session    
    
    # Скачивание дистрибутива

    try {
        downloadFile -url $url -targetFile $out_file -session $session    
    }
    catch {
        Invoke-WebRequest -Uri $url -Method Get -Websession $session -OutFile $out_file
    }

}

function downloadFile {
    Param($url, $targetFile, $session)

    Write-Host "Downloading $url"
    $uri = New-Object "System.Uri" "$url"
    $request = [System.Net.HttpWebRequest]::Create($uri)

    # Данные сессии
    $request.Headers = $session.Headers
    $request.CookieContainer = $session.Cookies
    $request.UseDefaultCredentials = $session.UseDefaultCredentials
    $request.Credentials = $session.Credentials
    $request.UserAgent = $session.UserAgent

    #$request.set_Timeout() #15 second timeout
    $response = $request.GetResponse()
    $chunk_size = 1024 * 1024
    $totalLength = [System.Math]::Floor($response.get_ContentLength()/$chunk_size)
    $responseStream = $response.GetResponseStream()
    $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
    $buffer = new-object byte[] 10KB
    $count = $responseStream.Read($buffer,0,$buffer.length)
    $downloadedBytes = $count
    while ($count -gt 0)
    {
        try {
            [System.Console]::CursorLeft = 0
            [System.Console]::Write("Downloaded {0} of {1} MB ", [System.Math]::Floor($downloadedBytes/$chunk_size), $totalLength)
        }
        catch {
        }
        $targetStream.Write($buffer, 0, $count)
        $count = $responseStream.Read($buffer,0,$buffer.length)
        $downloadedBytes = $downloadedBytes + $count
    }
    Write-Host "Finished Download"
    $targetStream.Flush()
    $targetStream.Close()
    $targetStream.Dispose()
    $responseStream.Dispose()
}

function Get-Distrib-Validate-Input{
    Param($username, $password, $version, $out_file)

    # Проверка что все параметры заполнены

    if ($username -isnot "String" -or -not $username) {
        throw 'username not filled'    
    }

    if ($password -isnot "String" -or -not $password) {
        throw 'password not filled'    
    }

    if ($version -isnot "String" -or -not $version) {
        throw 'version not filled'    
    }

    if ($out_file -isnot "String" -or -not $out_file) {
        throw 'out_file not filled'    
    }

    # Проверка формата версии

    $arr = $version.Split('.')
    if ($arr.length -ne 4) {
        throw 'version has unsupported format'    
    }

}

function Get-Distrib-link {
    Param($version, $session)

    Write-Host 'Getting distr link'

    $nick = Get-Distrib-Nick -version $version 

    # Страница ссылок на различные поставки платформы
    # * Технологическая платформа 1С:Предприятия для Windows
    # * Технологическая платформа 1С:Предприятия (64-bit) для Windows
    # * итд

    $header_page_url = 'https://releases.1c.ru/version_files?nick={Nick}&ver={version}'
    $header_page_url = $header_page_url.Replace('{Nick}', $nick)
    $header_page_url = $header_page_url.Replace('{version}', $version)

    $header_resp = Invoke-WebRequest -Uri $header_page_url -Method Get -UseBasicParsing -Websession $session
    Validate-Resp -resp $header_resp -Uri $header_page_url -Method Get

    # Страница для скачивания дистрибутива
    # * Скачать дистрибутив
    # * Скачать дистрибутив с зеркала

    #$anchor = '*>Технологическая платформа 1С:Предприятия для Windows<*'
    $anchor1 = '*\windows_' + $version.Replace('.', '_') + '.rar*'
    $anchor2 = '*\windows.rar*'
    
    $download_page_url_1 = $header_resp.Links.Where{$_.outerHTML -like $anchor1}.href   
    $download_page_url_2 = $header_resp.Links.Where{$_.outerHTML -like $anchor2}.href

    if ($null -ne $download_page_url_1) {
        $download_page_url = $download_page_url_1
    }elseif ($null -ne $download_page_url_2) {
        $download_page_url = $download_page_url_2    
    }else {
        throw 'download page link not found'     
    }
    
    $download_page_url = 'https://releases.1c.ru' + $download_page_url

    $download_resp = Invoke-WebRequest -Uri $download_page_url -Method Get -UseBasicParsing -Websession $session
    Validate-Resp -resp $download_resp -Uri $download_page_url -Method Get

    # Ссылка на скачивание

    $anchor = '*/file/get/*'
    $download_link = $download_resp.Links.Where{$_.outerHTML -like $anchor}.href

    if ($null -eq $download_link) {
        throw 'download link link not found'
    }elseif ($download_link.GetType().FullName -eq 'System.Object[]') {
        $download_link = $download_link[0]    
    }else {
        $download_link = $download_link    
    }

    return $download_link

}

function Get-Distrib-Nick {
    Param($version)

    return 'Platform' + $version.Substring(0,3).Replace('.', '')

}

function Get-session {
    Param($username, $password)

    Write-Host 'Authorization in 1c.ru'
    $releases = 'https://releases.1c.ru'
    $login = 'https://login.1c.ru/login'

    $releases_resp = Invoke-WebRequest -Uri $releases -Method Get -UseBasicParsing  
    Validate-Resp -resp $releases_resp -Uri $releases -Method Get

    $data = @{      
        _eventId = "submit"
        username = $username
        password = $password
        execution = $releases_resp.InputFields.Where{$_.name -eq "execution"}.value
        inviteCode = ""
    }
   
    $login_resp = Invoke-WebRequest -Uri $login -Method Post -UseBasicParsing -sessionVariable session -Body $data
    Validate-Resp -resp $login_resp -Uri $login -Method Post

    return $session

}

function Validate-Resp {
    Param($resp, $Uri, $Method)

    # Вывод информации о запросе

    $request_info = ''
    if ($Method -is "String") {
        $request_info = $request_info + '[' + $Method  + ']'   
    }     
    if ($Uri -is "String") {
        $request_info = $request_info + ' ' + $Uri     
    }
    if ($request_info){
        Write-Host $request_info    
    }

    # Вызов исключения

    if ($resp -isnot "Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject") {
        throw 'failed to get response from server'     
    }

    if ($resp.StatusCode -ge 300) {
        $msg = 'request failed code:' + $resp.StatusCode
        throw $msg
    }    
    else {
        $msg = 'success code:' + $resp.StatusCode
        Write-Host $msg   
    }     

}

#Get-Distrib -version '8.3.14.1779' -username '####' -password '####' -out_file 'w.rar'