#!/usr/bin/env bash
MainHelp(){
    echo -e "本工具可以管理项目各服务的启停和查询状态或配置文件解析结果
命令解析：
mc [操作] [操作各自子选项] ...
【操作】分为六类：
"
    echo -e "
启动: start
停止: stop
重启: restart
查询状态: list
查询配置解析结果: check
查看帮助菜单: [不填写操作名]/h/-h/help/--help
" | column -t

    echo -e "
具体写法举例：
mc list ...
功能：查看所有服务基本运行情况

mc start ...
功能：启动[一个/多个/所有]服务

mc stop ...
功能：停止[一个/多个/所有]服务

mc restart ...
功能：重启[一个/多个/所有]服务

mc
mc h
mc help
mc -h
mc --help
功能：以上五行命令任选其一均会打印此帮助菜单
"

echo -e "【操作各自子选项】不在本层帮助菜单中展示。
以【操作】 list 为例，想查看 list 后面可以使用哪些子选项可以使用以下任意一条命令来查看对应的子帮助菜单：

mc list h
mc list help
mc list -h
mc list --help
"
}

ListHelp(){
    echo -e "List功能可以查看项目各服务运行情况
可用命令："

    echo -e "
mc list
功能：查看所有服务基本运行情况

mc list more
功能：查看所有服务详细运行情况

mc list group
功能：查看配置文件中有哪些服务分组

mc list exclude
功能：查看配置文件中哪个/哪些服务在排除名单中

mc list h
mc list help
mc list -h
mc list --help
功能：以上四行命令任选其一均会打印此帮助菜单
"
}

CheckHelp(){
    echo -e "Check功能可以独立查看配置文件解析结果是否符合预期
可用命令："

    echo -e "
mc check
功能：查看配置文件解析结果是否符合预期

mc check h
mc check help
mc check -h
mc check --help
功能：以上四行命令任选其一均会打印此帮助菜单
"
}

StartHelp(){
    echo -e "Start功能可以启动项目中的各服务
可用命令："

    echo -e "
mc start
功能：一键启动一个或多个java服务

mc start h
mc start help
mc start -h
mc start --help
功能：以上四行命令任选其一均会打印此帮助菜单

mc start all
功能：一键启动所有可控java程序

按服务组名启动：
mc start group
功能：查看可启动的服务组名列表

mc start group aaa
功能：将组名为aaa中的所有子服务启动

mc start group aaa bbb ccc ...
功能：启动组名为aaa、bbb、ccc以及其他出现在命令行参数中的同名组内的所有子服务（即可以多个组几乎同时启动）


按服务名启动：
mc start rrr
功能：启动名为rrr的服务（rrr不能在排除列表中）

mc start rrr sss ttt ...
功能：启动名为rrr、sss、ttt以及其他出现在命令行参数中的同名服务（所有需要启动的服务名都不能存在于排除列表中）

"
}

StopHelp(){
    echo -e "Stop功能可以终止项目中的各服务进程
可用命令："

    echo -e "
mc start
功能：一键终止一个或多个java服务的进程

mc start h
mc start help
mc start -h
mc start --help
功能：以上四行命令任选其一均会打印此帮助菜单

mc start all
功能：一键终止所有可控java程序的进程

按服务组名终止进程：
mc start group
功能：查看可终止进程的服务组名列表

mc start group aaa
功能：终止组名为aaa中的所有子服务的进程

mc start group aaa bbb ccc ...
功能：终止组名为aaa、bbb、ccc以及其他出现在命令行参数中的同名组内的所有子服务进程（即可以多个组几乎同时终止）


按服务名终止进程：
mc start rrr
功能：启动名为rrr的服务（rrr不能在排除列表中）

mc start rrr sss ttt ...
功能：终止名为rrr、sss、ttt以及其他出现在命令行参数中的同名服务的进程（所有需要终止进程的服务名都不能存在于排除列表中）

"
}

RestartHelp(){
    echo -e "Restart功能可以重启项目中的各服务
可用命令："

    echo -e "
mc restart
功能：一键重启一个或多个java服务

mc restart h
mc restart help
mc restart -h
mc restart --help
功能：以上四行命令任选其一均会打印此帮助菜单

mc restart all
功能：一键重启所有可控java程序

按服务组名重启：
mc restart group
功能：查看可重启的服务组名列表

mc restart group aaa
功能：将组名为aaa中的所有子服务重启

mc restart group aaa bbb ccc ...
功能：重启组名为aaa、bbb、ccc以及其他出现在命令行参数中的同名组内的所有子服务（即可以多个组几乎同时重启）


按服务名重启：
mc restart rrr
功能：重启名为rrr的服务（rrr不能在排除列表中）

mc restart rrr sss ttt ...
功能：重启名为rrr、sss、ttt以及其他出现在命令行参数中的同名服务（所有需要重启的服务名都不能存在于排除列表中）

"
}

