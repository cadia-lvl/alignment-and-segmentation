<meta charset = "utf-8" />
<?php
/*
Author: Inga Rún Helgadóttir, Háskólinn í Reykjavík
Description Download subtitles for api.ruv.is/api/subtitles based on recording id

Running the script:
php local/extract_vtt.php <recoID> <outdir> &
or if have a list of recording ids in a file called recoid do
cat recoid | while read line ; do php local/extract_vtt.php $line /home/staff/inga/h2/transcripts; done
*/
set_time_limit(0);// allows infinite time execution of the php script itself
$recoid = $argv[1];
$outdir = $argv[2];
$url = 'https://api.ruv.is/api/subtitles/' . $recoid . '.mp4/is';
$ofile = $outdir . '/' . $recoid . '.vtt';

// Extract the audio
$ch = curl_init($url);
curl_setopt($ch, CURLOPT_HEADER, 0);
curl_setopt($ch, CURLOPT_NOBODY, 0);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT ,0); 
curl_setopt($ch, CURLOPT_TIMEOUT, 500);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, 1);
//curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 1);
curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (compatible; Chrome/22.0.1216.0)');
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
$output = curl_exec($ch);
if(curl_exec($ch) == false)
{
    echo 'recoID: ' . $recoid . "\n";
    echo 'Curl error: ' . curl_error($ch);
}
$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);
if ($status == 200) {
    file_put_contents($ofile, $output);
}
else
{
    echo 'recoID: ' . $recoid . "\n";
    echo 'status is what?! ' . $status . "\n";
    echo 'the output is a failure ' . $outifle . "\n";
}	
?>