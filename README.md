# Сбор на поездку

Контракт для сбора денег на поездку в ERC-20. После дедлайна организатор забирает взносы, если цель достигнута. Если нет, каждый участник возвращает свой вклад

Сбор работает через Transparent Proxy OpenZeppelin. В V2 добавлен `contributeFor`, чтобы можно было внести деньги за другого участника. При неудачном сборе возврат получает тот, за кого внесли деньги

## Сборка и тесты

Для запуска нужны Foundry версии 1.3.1 и Node.js 22 или новее. Solidity 0.8.28 загрузится при первой сборке сам

```bash
foundryup --install v1.3.1
git submodule update --init --recursive
npm ci --ignore-scripts
forge fmt --check
forge clean
forge build
forge test
```

Зависимости: OpenZeppelin Contracts и Contracts Upgradeable 5.4.0, Foundry Upgrades 0.4.2, Upgrades Core 1.46.0, forge-std 1.9.7. Версии сохранены в `package-lock.json` для удобства

Тесты обновления можно запустить отдельно:

```bash
forge test --match-path test/TripFundUpgrade.t.sol --force -vvv
```

Для проверки обновления используется валидатор OpenZeppelin, поэтому в настройках Foundry включен `ffi`

## Учет взносов

Токен, организатор, цель и дедлайн задаются при создании прокси через `initialize`. Повторно вызвать его или поменять параметры через отдельные функции нельзя. Организатор может вывести деньги при успехе, а обновить реализацию может владелец ProxyAdmin

Перед взносом нужно вызвать `approve` у токена, указав адрес прокси. Взносы принимаются до дедлайна, даже если цель уже достигнута. Ровно в дедлайн прием закрывается и становятся доступны выплаты

`totalRaised` - сумма всех взносов за время сбора, поэтому после выплат она не уменьшается. При успехе `withdraw` переводит организатору всю эту сумму, включая превышение цели. При провале `refund` возвращает вклад вызывающего и обнуляет его запись

Прямые переводы токенов на прокси не входят в `totalRaised` и не влияют на результат сбора. После вывода или возвратов они остаются на контракте

## Пример на Anvil

В одном терминале надо запустить сеть:

```bash
anvil
```

В другом терминале перейти в каталог проекта и развернуть токен и V1. Здесь используются стандартные аккаунты Anvil и локальная отправка транзакций через `--unlocked`

У тестового токена шесть знаков после запятой: `1000000` единиц равны одному токену. Цель сбора в примере - 1 000 токенов, срок - один час

```bash
export ETH_RPC_URL=http://127.0.0.1:8545
export ADMIN=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export ALICE=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export BOB=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
export CAROL=0x90F79bf6EB2c4f870365E785982E1f101E93b906
export ORGANIZER=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

export TOKEN_ADDRESS=$(forge create test/mocks/MockERC20.sol:MockERC20 \
  --rpc-url "$ETH_RPC_URL" --from "$ADMIN" --unlocked --broadcast --json \
  | node -pe 'JSON.parse(require("fs").readFileSync(0, "utf8")).deployedTo')

cast send "$TOKEN_ADDRESS" 'mint(address,uint256)' "$ALICE" 1000000000 \
  --from "$ADMIN" --unlocked
cast send "$TOKEN_ADDRESS" 'mint(address,uint256)' "$BOB" 1000000000 \
  --from "$ADMIN" --unlocked

export PROXY_ADMIN_OWNER=$ADMIN
export GOAL=1000000000
export DEADLINE=$(($(cast block latest --field timestamp) + 3600))

export PROXY_ADDRESS=$(forge script script/DeployTripFund.s.sol:DeployTripFund \
  --rpc-url "$ETH_RPC_URL" --sender "$ADMIN" --unlocked --broadcast --force --json \
  | node -pe 'JSON.parse(require("fs").readFileSync(0, "utf8").split("\n")[0]).returns.proxy.value')
```

Alice вносит 200 токенов, Bob - 300. Разрешение на списание сразу выдадим с запасом для следующих взносов

```bash
cast send "$TOKEN_ADDRESS" 'approve(address,uint256)' "$PROXY_ADDRESS" 300000000 \
  --from "$ALICE" --unlocked
cast send "$PROXY_ADDRESS" 'contribute(uint256)' 200000000 --from "$ALICE" --unlocked

cast send "$TOKEN_ADDRESS" 'approve(address,uint256)' "$PROXY_ADDRESS" 350000000 \
  --from "$BOB" --unlocked
cast send "$PROXY_ADDRESS" 'contribute(uint256)' 300000000 --from "$BOB" --unlocked

cast call "$PROXY_ADDRESS" 'totalRaised()(uint256)'
```

Теперь `totalRaised` равен `500000000`. Обновим тот же прокси до V2: Alice внесет еще 100 токенов за Carol, а Bob добавит 50 за себя

```bash
forge script script/UpgradeTripFund.s.sol:UpgradeTripFund \
  --rpc-url "$ETH_RPC_URL" --sender "$ADMIN" --unlocked --broadcast --force

cast send "$PROXY_ADDRESS" 'contributeFor(address,uint256)' "$CAROL" 100000000 \
  --from "$ALICE" --unlocked
cast send "$PROXY_ADDRESS" 'contribute(uint256)' 50000000 --from "$BOB" --unlocked

cast call "$PROXY_ADDRESS" 'contributions(address)(uint256)' "$CAROL"
cast call "$PROXY_ADDRESS" 'totalRaised()(uint256)'
```

Получится 650 токенов из необходимых 1 000. Переведем время к дедлайну и заберем вклады

```bash
cast rpc evm_setNextBlockTimestamp "$DEADLINE"
cast rpc evm_mine

cast send "$PROXY_ADDRESS" 'refund()' --from "$ALICE" --unlocked
cast send "$PROXY_ADDRESS" 'refund()' --from "$BOB" --unlocked
cast send "$PROXY_ADDRESS" 'refund()' --from "$CAROL" --unlocked

cast call "$TOKEN_ADDRESS" 'balanceOf(address)(uint256)' "$ALICE"
cast call "$TOKEN_ADDRESS" 'balanceOf(address)(uint256)' "$BOB"
cast call "$TOKEN_ADDRESS" 'balanceOf(address)(uint256)' "$CAROL"
cast call "$TOKEN_ADDRESS" 'balanceOf(address)(uint256)' "$PROXY_ADDRESS"
cast call "$PROXY_ADDRESS" 'totalRaised()(uint256)'
```

После возвратов у Alice будет 900 токенов, у Bob - 1 000, у Carol - 100, на прокси - 0. Деньги, которые Alice внесла за Carol, вернулись Carol. `totalRaised` по-прежнему равен `650000000`
