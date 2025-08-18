# Хуки автоматизированного добавления/удаления DNS записи API NIC.RU

Необходимы чтобы использовать их при перевыпуске сертификата certbot с параметрами:
- manual
- preferred-challenges dns

Создает DNS-запись вида:
```
<rr id="11111111"><name>_acme-challenge</name><idn-name>_acme-challenge</idn-name><ttl>300</ttl><type>TXT</type><txt><string>f8uh32887bf278bfnSDqed1</string></txt></rr>
```

#### Для запуска скрипта необходимо:

1. Заполнить данные NIC.RU в .env:
 - SERVICE - это название сервиса на NIC.RU (например MYDNSRECORDS)
 - ZONE - зона, в которую добавлять записи

2. Указать в файле nic_token.secret (права должны быть 600) необходимые токены:
 - NIC_CLIENT_AUTH - главный токен авторизации
 - NIC_REFRESH_TOKEN - токен для получения ACCESS-токена, он всегда находится в файле nic_token.secret и при получении нового ACCESS-токена меняется тоже, оба перезаписываются в файл nic_token.secret
 - NIC_ACCESS_TOKEN - временный токен для операций с зонами, действует 4 часа. В рамках хука auth.sh обновляется вместе с REFRESH-токеном.

3. Поправить путь до LOG_FILE и TOKEN_FILE в файле .env


#### Также можно получить записи DNS-зоны, предварительно вручную обновив токены.
```
./renew_token.sh

access:
fiu432h8f6yg327486g9v7263bfy82bf86y723vf632vg0f7632gv0f872h3f-98732h0f86y32bvf76v2307f62v0f
refresh:
gj45793gh08734bf87y234b0f7dt1v7d53v16d-032987gh-34897gb340876ybfg013798n=89hg4y289g7h4-2793
```
```
./check_record.sh

<response>
   <status>success</status>
   <data>
      <zone admin="123456/NIC-D" has-changes="false" id="123456" idn-name="example.com" name="example.com" service="MYDNSRECORDS">
         <rr id="66104500"><name>@</name><idn-name>@</idn-name><type>SOA</type><soa><mname><name>ns3-l2.nic.ru.</name><idn-name>ns3-l2.nic.ru.</idn-name></mname><rname><name>dns.nic.ru.</name><idn-name>dns.nic.ru.</idn-name></rname><serial>2022033079</serial><refresh>1440</refresh><retry>3600</retry><expire>2592000</expire><minimum>600</minimum></soa></rr>
      </zone>
   </data>
</response>
```