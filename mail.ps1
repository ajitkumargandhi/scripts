$smtp = New-Object System.Net.Mail.SmtpClient
$to = New-Object System.Net.Mail.MailAddress("user1@gmail.com")
$from = New-Object System.Net.Mail.MailAddress("user2@gmail.com")
#$attachment="D:\backup\disksize.txt"
$msg = New-Object System.Net.Mail.MailMessage($from, $to)
$msg.subject = ".net 10.0.0.3 - DNS2016 disk usage"
$msg.body = Get-Content -Path D:\backup\disksize.txt
#$msg.Attachments.Add($attachment)
$smtp.host = "smtp.gmail.com"
$SMTP.Port = 25
#$smtp.EnableSsl = $true
$smtp.send($msg)
