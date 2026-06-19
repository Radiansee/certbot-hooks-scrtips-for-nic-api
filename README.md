# Хуки автоматизированного добавления/удаления DNS записи API NIC.RU

Для получения `wildcard` SSL-сертификата единственный способ подтвердить владение доменом - это [DNS Plugins](https://eff-certbot.readthedocs.io/en/stable/using.html#dns-plugins).
DNS плагина для https://nic.ru нет, и поэтому написаны эти [manual-hooks](https://eff-certbot.readthedocs.io/en/stable/using.html#manual) для добавления dns записей на nic.ru для проверки LetsEncrypt. 

Необходимы, чтобы использовать их при перевыпуске сертификата certbot с параметрами:
- preferred-challenges dns
- manual-auth-hook
- manual-cleanup-hook


Auth-hook `auth.sh` создает DNS-запись вида:
```XML
<rr id="11111111"><name>_acme-challenge.DOMAIN_WITHOUT_ZONE</name><idn-name>_acme-challenge</idn-name><ttl>300</ttl><type>TXT</type><txt><string>validation_token</string></txt></rr>
```

Также Auth-hook записывает `Record id` этой записи в temp file, чтобы `cleanup.sh` удалил эту запись, после верификации LetsEncrypt.

В последнем обновлении скрипта был изменен механизм хранения большинства переменных в OpenBao (HashiVault).

> [!WARNING]
> При ручном использовании хуков (без Jenkins), необходимо указать переменные доступа к OpenBao в .env 

> [!IMPORTANT]  
> При работе с API NIC.ru необходим `Access token`, который действителен 4 часа. Получить его можно по API, использовав `Auth token` - это креды OAuth в формате base64 + `Refresh token`.
> `Refresh token` обновляется после каждого получения `Access token`, поэтому его необходимо где-то хранить. В данном случае он хранится в OpenBao.

#### Проект содержит модули:
- log.sh - Логирование. Создает log-file в папке logs/ , с названием хука.
- squadus.sh - Отправка алерта в Squadsus с произвольным сообщением.
- openbao.sh - Модуль для работы с openbao. Позволяет получать/перезаписывать данные.
- renew_token.sh - Получение NIC Access Token и одновременное обновление/запись нового refresh token в OpenBao.

#### Squadus
В файле .env необходимо указать путь OpenBao до кредов Squadus.

> [!WARNING]
> Если отправлять необходимости отправлять сообщения в Squadus нет, в скриптах надо удалить вызов функции `squadus_send`.


#### Для проверки можно использовать скрипт получения зоны.

```
./get_zone.sh

<response>
   <status>success</status>
   <data>
      <zone admin="123456/NIC-D" has-changes="false" id="123456" idn-name="example.com" name="example.com" service="MYDNSRECORDS">
         <rr id="66104500"><name>@</name><idn-name>@</idn-name><type>SOA</type><soa><mname><name>ns3-l2.nic.ru.</name><idn-name>ns3-l2.nic.ru.</idn-name></mname><rname><name>dns.nic.ru.</name><idn-name>dns.nic.ru.</idn-name></rname><serial>2022033079</serial><refresh>1440</refresh><retry>3600</retry><expire>2592000</expire><minimum>600</minimum></soa></rr>
      </zone>
   </data>
</response>
```