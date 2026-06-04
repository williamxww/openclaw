name: start-go
steps:
  - id: ready
    run: printf 'WE ARE READY...\n'

  - id: confirm
    approval: 确认开始？
    stdin: $ready.stdout

  - id: one
    run: printf '1\n'
    when: $confirm.approved

  - id: gap1
    run: sleep 1
    when: $confirm.approved

  - id: two
    run: printf '2\n'
    when: $confirm.approved

  - id: gap2
    run: sleep 1
    when: $confirm.approved

  - id: three
    run: printf '3\n'
    when: $confirm.approved

  - id: gap3
    run: sleep 1
    when: $confirm.approved

  - id: done
    run: printf '结束\n'
    when: $confirm.approved
