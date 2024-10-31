#!/bin/bash
# version: 1.0.1
# 前置全局检测参数初始化和收集
# 规定sqlbak只通过安装包的形式安装，而非通过包内文件直接放置的方式实现部署
# 只有非涉密系统且联网时才允许更新和[卸载(仅限root)]，其他情况一律禁用更新和卸载
# 且更新也仅仅是联网下载安装包，卸载也是本地卸载安装包。
# 即 isClassified=0 && networkValid=1
isClassified=0
networkValid=0

IsClassifiedSystem(){
    # 0 = 否
    # 1 = 是
    # 2 = 暂未见过的涉密系统
    echo "date" > /tmp/test_classified.sh
    if ! bash /tmp/test_classified.sh >/dev/null 2>&1; then
        if bash <(cat /tmp/test_classified.sh) >/dev/null 2>&1; then
            isClassified=1
        else
            isClassified=2
        fi
    else
        isClassified=0
    fi
    rm -rf /tmp/test_classified.sh
}

IsNetworkValid(){
    # 0 = 无网络
    # 1 = 网络正常
    if timeout 5s ping -c2 -W1 www.baidu.com > /dev/null 2>&1; then
        networkValid=1
    else
        networkValid=0
    fi
}

IsClassifiedSystem

# 全局颜色(适配涉密机)

if ! which tput >/dev/null 2>&1 || [ "${isClassified}" -eq 1 ]; then
    NORM="\033[39m"
    RED="\033[31m"
    GREEN="\033[32m"
    TAN="\033[33m"
    CYAN="\033[36m"
else
    NORM=$(tput sgr0)
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    TAN=$(tput setaf 3)
    CYAN=$(tput setaf 6)
fi

formatPrint() {
    printf "${NORM}%s${NORM}\n" "$@"
}
formatInfo() {
    printf "${CYAN}➜ %s${NORM}\n" "$@"
}
formatInfoNoBlank() {
    printf "${CYAN}%s${NORM}\n" "$@"
}
formatSuccess() {
    printf "${GREEN}✓ %s${NORM}\n" "$@"
}
formatSuccessNoBlank() {
    printf "${GREEN}%s${NORM}\n" "$@"
}
formatWarning() {
    printf "${TAN}⚠ %s${NORM}\n" "$@"
}
formatWarningNoBlank() {
    printf "${TAN}%s${NORM}\n" "$@"
}
formatError() {
    printf "${RED}✗ %s${NORM}\n" "$@"
}
formatErrorNoBlank() {
    printf "${RED}%s${NORM}\n" "$@"
}

todayDateMore=
todayDateLess=
isNonRootUser=
localParentPath=
sqlBakFile=
etcPath=
logPath=
cronPath=
yqFile=
yamlFile=
yamlFile1=
yamlFile2=
otherCronFile=

firstOption=
dbSWName=
mysqlIP=
mysqlPort=
mysqlUser=
mysqlPass=
backupPath=
expiresDays=
cronFormat=
dbType=
excludeDatabaseList=()
databaseList=()
finalBackupDatabaseList=()

# wrongDatabaseList
# 特指mysql/mariadb中不存在的数据库名，比如填写好sqlbak的配置文件后，后期人为删掉了某个在配置文件中提到的数据库但没更新sqlbak配置文件导致批量备份失败
#
# wrongTaskList
# 特指配置文件中存在但实际无法连接的数据库，比如填写好sqlbak的配置文件后，后期人为修改了数据库密码但没更新sqlbak配置文件导致无法连接
wrongDatabaseList=()
wrongTaskList=

mysqlPath=
mysqldumpPath=
specifiedTaskList=
timingSegmentList=

taskList=()
loseControlTask=()
installedTask=()
notInstalledTask=()
repairSegmentTimerList=()
taskListNotExistList=()
needRebuildSystemTimer=0

SetConstantAndVariableByCurrentUser(){
    # 当前日期时间（时分秒不能用冒号表示间隔，否则centos7的tar命令无法解压文件名包含这种时间格式的压缩包）
    todayDateMore=$(date +%Y-%m-%d_%H-%M-%S)
    todayDateLess=$(date +%Y-%m-%d)

    if [[ $0 =~ "/dev/fd" ]]; then
        formatError "此构建脚本禁止使用进程替换方式运行，退出中"
        exit 1
    fi
    local sqlBakPath yqFileName
    sqlBakFile=$(readlink -f "$0")
    sqlBakPath=$(dirname "${sqlBakFile}")

    # 规定与sqlbak文件同目录的yq解析器是最高调用优先级，没有再去系统中找
    case "$(arch)" in
    "aarch64")
        yqFileName="yq_linux_arm64"
        ;;
    "x86_64")
        yqFileName="yq_linux_amd64"
        ;;
    esac

    if [ $EUID -eq 0 ] && [[ $(grep -o "^$(whoami):.*" /etc/passwd | cut -d':' -f3) -eq 0 ]]; then
        isNonRootUser=0
        etcPath="/etc"
        cronPath="/etc/cron.d"
        logPath="/var/log/sqlbak"
        yamlFile1="/etc/sqlbak.yml"
        yamlFile2="/etc/sqlbak.yaml"
        yqFile="/usr/bin/${yqFileName}"
    else
        isNonRootUser=1
        localParentPath="/home/$(whoami)/.local/sqlbak"
        etcPath="${localParentPath}/config"
        cronPath="${localParentPath}/sqlbakcron"
        logPath="${localParentPath}/log"
        yamlFile1="${localParentPath}/config/sqlbak.yml"
        yamlFile2="${localParentPath}/config/sqlbak.yaml"
        otherCronFile="${localParentPath}/sqlbakcron/other-cron"
        yqFile="${localParentPath}/bin/${yqFileName}"
    fi

    # 以下调试用，用于覆盖默认的标准路径。
    if [[ -f "${sqlBakPath}/${yqFileName}" ]]; then
        yqFile="${sqlBakPath}/${yqFileName}"
    fi
    if [[ -f "${sqlBakPath}/sqlbak.yml" ]]; then
        yamlFile="${sqlBakPath}/sqlbak.yml"
        yamlFile1=""
        yamlFile2=""
    elif [[ -f "${sqlBakPath}/sqlbak.yaml" ]]; then
        yamlFile="${sqlBakPath}/sqlbak.yaml"
        yamlFile1=""
        yamlFile2=""
    fi

    # 设置定时任务文件名前缀
    prefixCronFile="mysql-backup-task@_"

    formatSuccess "全局变量初始化完成"
}

CheckDependence(){
    formatInfo "正在检查环境依赖..."
    # 对备份工具进行定位，如果找不到则退出
    if which mysqldump >/dev/null 2>&1; then
        mysqldumpPath=$(which mysqldump)
    else
        formatError "找不到mysqldump，退出中"
        exit 1
    fi
    if which mysql >/dev/null 2>&1; then
        mysqlPath=$(which mysql)
    else
        formatError "找不到mysql，退出中"
        exit 1
    fi

    # 为非root用户创建工具正常工作所需的必要路径，后面会用到
	if [ "${isNonRootUser}" -eq 1 ]; then
	    [[ ! -d "${etcPath}" ]] && mkdir -p "${etcPath}"
	    [[ ! -d "${cronPath}" ]] && mkdir -p "${cronPath}"
	    [[ ! -d "${logPath}" ]] && mkdir -p "${logPath}"
	elif [ "${isNonRootUser}" -eq 0 ]; then
	    [[ ! -d "${logPath}" ]] && mkdir -p "${logPath}"
	fi

	# 检查配置文件解析工具工作是否正常，如果不正常或丢失则退出
    if [ ! -f "${yqFile}" ]; then
        formatError "配置文件解析工具丢失，退出中"
        exit 1
    elif [ ! -x "${yqFile}" ]; then
        formatError "配置文件解析工具未无可执行权限，退出中"
        exit 1
    elif ! "${yqFile}" -V|awk '{print $NF}' >/dev/null 2>&1; then
        formatError "配置文件解析工具损坏，无法解析，退出中"
        exit 1
    fi

    if [[ -z "${yamlFile1}" ]] && [[ -z "${yamlFile2}" ]]; then
        :
    elif [ -f "${yamlFile1}" ] && [ -f "${yamlFile2}" ]; then
        formatError "发现两种配置文件，请手动检查并只保留一个配置文件，退出中"
        echo "${yamlFile1}"
        echo "${yamlFile2}"
        exit 1
    elif [ ! -f "${yamlFile1}" ] && [ ! -f "${yamlFile2}" ]; then
        formatWarning "未发现配置文件，正在生成模板..."
        yamlFile="${yamlFile1}"
        if GenerateProfile; then
            formatSuccess "模板配置文件已生成，请修改后重新运行，以下是配置文件绝对路径："
            echo "${yamlFile}"
        else
            formatError "生成模板配置文件时出现未知情况，请联系作者排查，退出中"
            exit 1
        fi
        exit 0
    elif [ -f "${yamlFile1}" ];then
        yamlFile="${yamlFile1}"
    elif [ -f "${yamlFile2}" ];then
        yamlFile="${yamlFile2}"
    fi

	formatSuccess "环境依赖检查完成"
}

CheckInstallStatus(){
    # 以下echo的内容就是注释，ide中颜色明亮点方便调试
echo "
1: 配置存在
0: 配置不存在
root用户: 系统定时=定时分段

系统定时	定时分段	配置文件	结果
非root：
1		1		1		已安装
0		0		1		未安装
1		1		0		失控
1		0		0		失控
0		1		0		失控
1		0		1		自修复（添加定时分段）
0		1		1		自修复（重建系统定时）
0		0		0		-

root：
		1		1		已安装
		1		0		失控
		0		1		未安装
		0		0		-
" > /dev/null
    local i j sameNameTaskList

    # 检查配置文件是否存在yq能检测的报错
    if ! ${yqFile} '.' "${yamlFile}" >/dev/null; then
        formatError "配置文件出现异常，已输出报错信息，退出中"
        exit 1
    fi

    # 检查相同的任务名，如果存在，则报错退出，这个检测任务yq做不到
    mapfile -t sameNameTaskList < <(grep -o '^.*:' "${yamlFile}" | grep -v "^ \|^#" | cut -d':' -f1 | uniq -d)
    if [ "${#sameNameTaskList[@]}" -gt 0 ]; then
        formatError "禁止存在相同任务名，退出中，以下是重名任务："
        for j in "${sameNameTaskList[@]}"; do
            formatWarningNoBlank "${j}"
        done
        exit 1
    fi

    # yamlStreamTaskList: 系统定时
    # timingSegmentList: 定时分段
    # taskList: 配置文件
    # 重置数组防止被事先存入了元素
    taskList=()
    loseControlTask=()
    installedTask=()
    notInstalledTask=()
    mapfile -t taskList < <(${yqFile} '.[]|key' "${yamlFile}")
    mapfile -t timingSegmentList < <(find "${cronPath}" -name "${prefixCronFile}*"|awk -F '@_' '{print $NF}')

    if [ "${isNonRootUser}" -eq 0 ]; then
        # 配置文件中任务名对比系统已有定时的任务名，对比相同的名称组成：已安装任务数组
        for i in "${taskList[@]}" ; do
            if printf '%s\0' "${timingSegmentList[@]}" | grep -Fxqz -- "${i}"; then
                mapfile -t -O "${#installedTask[@]}" installedTask < <(echo "${i}")
            fi
        done

        # 配置文件中任务去掉已安装任务组成：未安装任务数组
        for i in "${taskList[@]}" ; do
            if ! printf '%s\0' "${installedTask[@]}" | grep -Fxqz -- "${i}"; then
                mapfile -t -O "${#notInstalledTask[@]}" notInstalledTask < <(echo "${i}")
            fi
        done

        # 系统已有定时的任务列表去掉已安装任务组成：失去控制的任务数组
        for i in "${timingSegmentList[@]}" ; do
            if ! printf '%s\0' "${installedTask[@]}" | grep -Fxqz -- "${i}"; then
                mapfile -t -O "${#loseControlTask[@]}" loseControlTask < <(echo "${i}")
            fi
        done
    else
        local systemCronToYamlStream yamlStreamTaskList temp1Task temp0Task
        systemCronToYamlStream=$(crontab -l 2>/dev/null|grep "^#%"|sed 's/^#%//g')
        mapfile -t -O "${#yamlStreamTaskList[@]}" yamlStreamTaskList < <(echo "${systemCronToYamlStream}"|${yqFile} '.[]|key')

        # 配置文件中任务名对比定时分段任务名，对比相同的名称组成：temp1Task，定时分段不存在的话组成：temp0Task
        temp0Task=()
        temp1Task=()
        for i in "${taskList[@]}" ; do
            if printf '%s\0' "${timingSegmentList[@]}" | grep -Fxqz -- "${i}"; then
                mapfile -t -O "${#temp1Task[@]}" temp1Task < <(echo "${i}")
            else
                mapfile -t -O "${#temp0Task[@]}" temp0Task < <(echo "${i}")
            fi
        done

        # 系统定时1-定时分段1-配置文件1->installedTask: 已安装
        # 系统定时0-定时分段1-配置文件1->repairSystemTimerList: 自修复（重建系统定时）
        if [ "${#temp1Task[@]}" -gt 0 ]; then
            for i in "${temp1Task[@]}" ; do
                if printf '%s\0' "${yamlStreamTaskList[@]}" | grep -Fxqz -- "${i}"; then
                    mapfile -t -O "${#installedTask[@]}" installedTask < <(echo "${i}")
                else
                    needRebuildSystemTimer=1
                fi
            done
        fi

        # 系统定时1-定时分段0-配置文件1->repairSegmentTimerList: 自修复（添加定时分段）
        # 系统定时0-定时分段0-配置文件1->notInstalledTask: 未安装
        if [ "${#temp0Task[@]}" -gt 0 ]; then
            for i in "${temp0Task[@]}" ; do
                if printf '%s\0' "${yamlStreamTaskList[@]}" | grep -Fxqz -- "${i}"; then
                    mapfile -t -O "${#repairSegmentTimerList[@]}" repairSegmentTimerList < <(echo "${i}")
                else
                    mapfile -t -O "${#notInstalledTask[@]}" notInstalledTask < <(echo "${i}")
                fi
            done
        fi

        # 定时分段任务名对比配置文件中任务名，配置文件中不存在的任务名组成：taskListNotExistList（删除残留定时分段）
        # 系统定时随意-定时分段1-配置文件0，均删除多余分段后重建系统定时
        for i in "${timingSegmentList[@]}" ; do
            if ! printf '%s\0' "${taskList[@]}" | grep -Fxqz -- "${i}"; then
                mapfile -t -O "${#taskListNotExistList[@]}" taskListNotExistList < <(echo "${i}")
            fi
        done

        # 系统定时1-定时分段0-配置文件0，直接重建系统定时
        if [ "${#taskListNotExistList[@]}" -eq 0 ]; then
            for i in "${yamlStreamTaskList[@]}" ; do
                if ! printf '%s\0' "${taskList[@]}" | grep -Fxqz -- "${i}"; then
                    needRebuildSystemTimer=2
                    break
                fi
            done
        fi
    fi
}

AutoRepair(){
    local i flag
    flag=0
    if [ "${isNonRootUser}" -eq 0 ]; then
        if [ "${#loseControlTask[@]}" -gt 0 ]; then
            for i in "${loseControlTask[@]}" ; do
                rm -rf  "${cronPath:?}/${prefixCronFile}${i}"
            done
            formatWarning "发现系统中存在本工具配置文件中不存在的备份任务！已清理"
            flag=1
        fi
    elif [ "${isNonRootUser}" -eq 1 ]; then
        [ -f "${cronPath}"/final-cron-install-file ] && rm -rf "${cronPath}"/final-cron-install-file
        # 删除残留定时分段
        if [ "${#taskListNotExistList[@]}" -gt 0 ]; then
            for i in "${taskListNotExistList[@]}" ; do
                rm -rf "${cronPath:?}/${prefixCronFile}${i}"
            done
            needRebuildSystemTimer=3
            formatWarning "发现系统中存在本工具配置文件中不存在的备份任务！已清理"
            flag=2
        fi

        # 添加定时分段
        if [ "${#repairSegmentTimerList[@]}" -gt 0 ]; then
            for i in "${repairSegmentTimerList[@]}" ; do
                ParseYaml "${i}"
                InstallTask "${i}"
            done
            formatWarning "发现系统中存在部分配置丢失的备份任务！已修复"
            flag=3
        fi

        # 重建系统定时
        if [ "${needRebuildSystemTimer}" -gt 0 ]; then
            timingSegmentList=()
            mapfile -t timingSegmentList < <(find "${cronPath}" -name "${prefixCronFile}*"|awk -F '@_' '{print $NF}')
            for i in "${timingSegmentList[@]}" ; do
                cat "${cronPath}/${prefixCronFile}${i}" >> "${cronPath}"/final-cron-install-file
            done
            if [ -f "${cronPath}"/final-cron-install-file ]; then
                crontab "${cronPath}"/final-cron-install-file
                rm -rf "${cronPath}"/final-cron-install-file
                formatWarning "已根据已安装的备份任务重建系统备份计划"
            fi
            flag=4
        fi
    fi
    if [ "${flag}" -gt 0 ]; then
        CheckInstallStatus
        formatSuccess "已重新读取修正后的任务安装环境"
    else
        formatSuccess "比对完成，未发现异常"
    fi
}

GenerateProfile() {
    cat >"${yamlFile}" <<EOF
# mysql/mariadb 有一些默认库理论上可以不备份，备份的话有概率会导致备份错误但从流程设计上不会影响到整个备份的执行。
# 以下是非必须备份的数据库的统计和介绍：
# information_schema：此库包含数据库的元数据信息，如表结构、列信息等，但不包含用户数据。
# performance_schema：此库用于收集和分析数据库的性能统计数据，不存储用户数据。
# sys：该库为数据库管理和性能分析提供便捷视图，但也不包含实际用户数据。
# test：该库是测试数据库，通常用于测试和实验，不建议存储重要数据。

# 以下有五组配置，第一组是为每个键进行解释，实际本工具有四个模板，第二到第五这四组配置均为独立的模板可供选择
# 不会用 yaml 的请从以下四种模板中根据实际情况选择并使用(别忘了删除开头的 # 号)
#name123: # namexxx是为当前任务的别名，任务名称包括name在内完全可以自定义，比如local、456等等
#  ip: 2.2.2.2 # 数据库所在服务器的 ip，如果sqlbak和需要备份的数据库在同一个服务器上，则 ip 的值允许写 localhost 或 127.0.0.1
#  port: 3307 # 数据库连接端口号
#  user: root # 数据库连接用户名
#  password: 5678 # 数据库连接密码
#  database: aaa # 如果只有一个数据库就不用写成列表样式（一个库写成列表样式也支持的），如果希望所有库都备份，则此处 aaa 替换成 all
#  backup-path: /opt/test # 执行当前工具所在节点下的备份根路径
#  expires-days: 10 # 自动清理生成多少天后的过期备份文件，0为关闭自动删除功能
#  cron-format: "0 1 * * *" # 此值在本工具中没有合法性判断流程，可自行查阅配置教程或搜索crontab在线生成工具来生成可用的五段式定时写法，必须用双引号将写法括起来否则会报错

## 例1：一个基本单元中只有一个数据库需要备份
#name1:
#  ip: localhost
#  port: 3306
#  user: root
#  password: root
#  backup-path: /opt/backup/project
#  expires-days: 10
#  cron-format: "* * * * *"
#  database: aaa
#
## 例2：一个基本单元中有多个数据库需要备份(使用列表形式)
#name2:
#  ip: 127.0.0.1
#  port: 3307
#  user: root
#  password: 1234
#  backup-path: /opt/backup/multiple-sql
#  expires-days: 10
#  cron-format: "0 1 * * *"
#  database:
#    - aaa
#    - bbb
#    - ccc
#
## 例3：一个基本单元中只有一个数据库在所有库备份时被排除
#name3:
#  ip: 10.0.0.10
#  port: 3306
#  user: root
#  password: root
#  backup-path: /opt/backup/project
#  expires-days: 10
#  cron-format: "* * * * *"
#  exclude-database: aaa
#
## 例4：一个基本单元中有多个数据库在所有库备份时被排除(使用列表形式)
#name4:
#  ip: 192.168.1.10
#  port: 3307
#  user: root
#  password: 1234
#  backup-path: /opt/backup/multiple-sql
#  expires-days: 10
#  cron-format: "0 1 * * *"
#  exclude-database:
#    - aaa
#    - bbb
#    - ccc
EOF
}

ParseYaml() {
    local paramList specifiedTaskParamList paramName taskName
    taskName="${1}"
    paramList=(
        "ip"
        "port"
        "user"
        "password"
        "backup-path"
        "expires-days"
        "cron-format"
        "database"
        "exclude-database"
    )

    # 首先确认yml文件可以被正常解析
    if ! ${yqFile} '.' "${yamlFile}" >/dev/null; then
        formatError "配置文件出现异常，已输出报错信息，退出中"
        exit 1
    fi

    # 检测程序工作所需键在配置文件中是否存在
    # 检测键database和exclude-database是否同时存在，必须存在其中之一且不能同时存在
    mapfile -t specifiedTaskParamList < <(${yqFile} '.'"${taskName}"'.[]|key' "${yamlFile}")
    local dbCount edbCount sumCount
    dbCount=0
    edbCount=0
    sumCount=0

    for paramName in "${paramList[@]}" ; do
        if
        [ "${paramName}" != "database" ] &&
        [ "${paramName}" != "exclude-database" ] &&
        [ "${paramName}" != "expires-days" ]; then
            if ! printf '%s\n' "${specifiedTaskParamList[@]}" | grep -qF "${paramName}"; then
                formatError "缺少配置选项: ${paramName}，退出中"
                exit 1
            fi
        fi
    done

    if printf '%s\n' "${specifiedTaskParamList[@]}" | grep -qE "^database$"; then
        dbCount=$((dbCount + 1))
    fi
    if printf '%s\n' "${specifiedTaskParamList[@]}" | grep -qE "^exclude-database$"; then
        edbCount=$((edbCount + 1))
    fi
    sumCount=$((dbCount + edbCount))
    if [ "${sumCount}" -ne 1 ]; then
        formatError "database 和 exclude-database 配置选项只能设置其一，不能同时存在或同时不存在，退出中"
        exit 1
    elif [ "${dbCount}" -gt 0 ]; then
        dbType="include"
    elif [ "${edbCount}" -gt 0 ]; then
        dbType="exclude"
    fi

    # 解析赋值变量
    mysqlIP=$(${yqFile} '.'"${taskName}"'.ip' "${yamlFile}")
    mysqlPort=$(${yqFile} '.'"${taskName}"'.port' "${yamlFile}")
    mysqlUser=$(${yqFile} '.'"${taskName}"'.user' "${yamlFile}")
    mysqlPass=$(${yqFile} '.'"${taskName}"'.password' "${yamlFile}")
    backupPath=$(${yqFile} '.'"${taskName}"'.backup-path' "${yamlFile}")
    expiresDays=$(${yqFile} '.'"${taskName}"'.expires-days' "${yamlFile}")
    cronFormat=$(${yqFile} '.'"${taskName}"'.cron-format' "${yamlFile}")

    # 根据dbType的值选分支，判断数据库是单库名还是列表库名（全库备份的库名是 all），最终均收纳到databaseList或excludeDatabaseList数组中
    databaseList=()
    excludeDatabaseList=()
    case "${dbType}" in
    "include")
        mapfile -t -O "${#databaseList[@]}" databaseList < <(${yqFile} '.'"${taskName}"'.database.[]' "${yamlFile}")
        if [ "${#databaseList[@]}" -eq 0 ]; then
            if [ -n "$(${yqFile} '.'"${taskName}"'.database' "${yamlFile}")" ]; then
                databaseList[0]=$(${yqFile} '.'"${taskName}"'.database' "${yamlFile}")
            fi
        fi
        ;;
    "exclude")
        mapfile -t -O "${#excludeDatabaseList[@]}" excludeDatabaseList < <(${yqFile} '.'"${taskName}"'.exclude-database.[]' "${yamlFile}")
        if [ "${#excludeDatabaseList[@]}" -eq 0 ]; then
            if [ -n "$(${yqFile} '.'"${taskName}"'.exclude-database' "${yamlFile}")" ]; then
                excludeDatabaseList[0]=$(${yqFile} '.'"${taskName}"'.exclude-database' "${yamlFile}")
            fi
        fi
    esac


    # 对变量值进行调整和筛选判断
    # 配置文件所有键值必须有值
    if [ -z "${mysqlIP}" ] ||
    [ -z "${mysqlPort}" ] ||
    [ -z "${mysqlUser}" ] ||
    [ -z "${mysqlPass}" ] ||
    [ -z "${backupPath}" ] ||
    [ -z "${expiresDays}" ] ||
    [ -z "${cronFormat}" ]; then
        formatError "存在部分键值为空，请检查，退出中"
        exit 1
    fi

    case "${dbType}" in
    "include")
        if [ "${#databaseList[@]}" -eq 0 ]; then
            formatError "待备份数据库键值为空，请检查，退出中"
            exit 1
        fi
        ;;
    "exclude")
        if [ "${#excludeDatabaseList[@]}" -eq 0 ]; then
            formatError "待排除数据库键值为空，请检查，退出中"
            exit 1
        fi
        ;;
    esac
    # 非根目录且路径末尾有/则去掉路径末尾/
    if [[ ! ${backupPath} =~ ^/ ]]; then
        formatError "备份路径禁止使用相对路径，退出中"
        exit 1
    elif [[ ${backupPath} =~ /$ ]]; then
        backupPath="${backupPath%/}"
    fi

    # 非root用户必须对备份路径进行每一层级目录的权限排查，以避免无法写入备份文件的问题。
    # 已知只要非其他系统已存在用户的家目录，路径末端文件夹属主是当前用户，则内部无限层级均可由当前用户创建，因此判断条件有三个:
    # 1. 备份路径文件夹不是其他用户的家目录下的子文件夹
    # 2. 如果需要写入文件的路径存在且不是根目录，则写入文件的文件夹属主必须是当前用户
    # 3. 如果需要写入文件的文件夹不存在，则向上递归直到有文件夹存在，之后进入第二个判断
    #
    # root用户绝大部分路径均可访问写入，但个别路径是系统限制无法写入，因此需要猜测是否可写，所以流程分两步：
    # 1. 如果路径存在，则尝试直接写入文件检查是否可写
    # 2. 如果路径不存在，则向上递归直到有文件夹存在，之后进入第一个判断
    local parentPath invalidPath i lastBakFolder
    parentPath="${backupPath}"
    if [ "${isNonRootUser}" -eq 1 ]; then
        mapfile -t invalidPath < <(awk -F ':' '{print $6}' /etc/passwd|grep -v "/$")
        for i in "${invalidPath[@]}"; do
            if [[ "${parentPath}" =~ ^${i} ]] && [[ ! ${parentPath} =~ ^$HOME ]]; then
                formatError "指定的备份路径禁止设置为系统已存在用户但非当前登录用户的家目录及其(${i})中的子目录！退出中"
                exit 1
            fi
        done
        while true; do
            if [ -d "${parentPath}" ]; then
                if [ "${parentPath}" == "/" ]; then
                        formatError "非root用户禁止在系统根目录存放备份的数据库存档，请重新指定路径"
                        formatError "退出中"
                        exit 1
                elif [ ! -O "${parentPath}" ]; then
                    lastBakFolder=$(awk -F '/' '{print $NF}' <<< "${parentPath}")
                    formatError "当前用户没有权限将数据库备份到设置的备份路径下"
                    formatError "请在root用户下将备份文件存放的文件夹的权限(${lastBakFolder})设置为当前用户($(whoami))可完全访问，退出中"
                    exit 1
                else
                    break
                fi
            else
                parentPath=$(dirname "${parentPath}")
            fi
        done
    elif [ "${isNonRootUser}" -eq 0 ]; then
        while true; do
            if [ -d "${parentPath}" ]; then
                if ! touch "${parentPath}"/testfile >/dev/null 2>&1; then
                    formatError "此路径在涉密或限制性系统中无法作为备份路径: ${parentPath}"
                    formatError "退出中"
                    exit 1
                else
                    rm -rf "${parentPath}"/testfile
                    break
                fi
            else
                parentPath=$(dirname "${parentPath}")
            fi
        done
    fi

    # 检查过期天数合法性
    case ${expiresDays} in
        ''|*[!0-9]*)
            formatError "过期天数只能是非负整数（禁止+-符号），退出中"
            exit 1
        ;;
    esac

    # 检查数据库连接性
    if ! "${mysqlPath}" -h"${mysqlIP}" -P"${mysqlPort}" -u"${mysqlUser}" -p"${mysqlPass}" -e "exit" >/dev/null 2>&1; then
        formatError "数据库无法连接，请检查 IP、端口号、用户名、密码是否有错"
        formatError "实际执行的时候会跳过该任务，请修正并重新运行"
        wrongTaskList="${taskName}"
        return 1
    fi

    # 检测该任务名对应的数据库连的是mysql还是mariadb
    local dbSWNameTemp
    dbSWNameTemp=$(mysql -NB -h"${mysqlIP}" -P"${mysqlPort}" -u"${mysqlUser}" -p"${mysqlPass}" -e 'select @@version_comment;' 2>/dev/null)
    if [[ "${dbSWNameTemp}" =~ "MariaDB" ]]; then
        dbSWName="MariaDB"
    elif [[ "${dbSWNameTemp}" =~ "MySQL" ]]; then
        dbSWName="MySQL"
    fi

    # 检查配置文件中指定备份的数据库名是否存在
    local i
    mapfile -t databaseListFromSource < <("${mysqlPath}" -NB -h"${mysqlIP}" -P"${mysqlPort}" -u"${mysqlUser}" -p"${mysqlPass}" -e "show databases;" 2>/dev/null)
    wrongDatabaseList=()
    finalBackupDatabaseList=()
    case "${dbType}" in
    "include")
        if [[ "${databaseList[0]}" == "all" ]]; then
            finalBackupDatabaseList=("${databaseListFromSource[@]}")
        else
            for i in "${databaseList[@]}"; do
                if ! printf '%s\n' "${databaseListFromSource[@]}"|grep -qE "^${i}$"; then
                    mapfile -t -O "${#wrongDatabaseList[@]}" wrongDatabaseList < <(echo "${i}")
                else
                    mapfile -t -O "${#finalBackupDatabaseList[@]}" finalBackupDatabaseList < <(echo "${i}")
                fi
            done
        fi
        ;;
    "exclude")
        for i in "${excludeDatabaseList[@]}"; do
            if ! printf '%s\n' "${databaseListFromSource[@]}"|grep -qE "^${i}$"; then
                mapfile -t -O "${#wrongDatabaseList[@]}" wrongDatabaseList < <(echo "${i}")
            fi
        done
        for i in "${databaseListFromSource[@]}"; do
            if ! printf '%s\n' "${excludeDatabaseList[@]}"|grep -qE "^${i}$"; then
                mapfile -t -O "${#finalBackupDatabaseList[@]}" finalBackupDatabaseList < <(echo "${i}")
            fi
        done
        ;;
    esac
    if [ "${#wrongDatabaseList[@]}" -gt 0 ]; then
        formatError "源 ${dbSWName} 中不存在以下配置文件中指定的数据库名:"
        for i in "${wrongDatabaseList[@]}" ; do
            formatWarningNoBlank "${i}"
        done
        formatError "实际执行的时候将跳过以上数据库，请修正并重新运行"
    fi
}

# 安装策略：
# 无论一次安装多少个任务，总是一个任务设置一个任务记录文件，里面有已注释的该任务的详细配置和实际可用的定时写法，同任务被多次安装的话会完全覆盖而非追加，以下是root和非root用户安装区别
# 1. root：每个任务记录文件都是一个定时功能，无需后续操作
# 2. 非root：任何任务记录文件均不会执行，而是生成一个或多个任务记录文件后，将指定的任务记录文件内的内容组合成一个最终文件，然后将最终文件安装进系统定时任务后删除，非root用户安装不同定时任务文件会覆盖而非追加故用此方法实现
InstallTask(){
    local taskName="${1}"
    # 为每一个任务拼装一个定时文件
    cat > "${cronPath}/${prefixCronFile}${taskName}" << EOF
#%${taskName}:
#%  ip: ${mysqlIP}
#%  port: ${mysqlPort}
#%  user: ${mysqlUser}
#%  password: ${mysqlPass}
#%  backup-path: ${backupPath}
#%  expires-days: ${expiresDays}
#%  cron-format: "${cronFormat}"
EOF
    case "${dbType}" in
    "include")
        if [ "${#databaseList[@]}" -eq 1 ]; then
            echo "#  database: ${databaseList[0]}" >> "${cronPath}/${prefixCronFile}${taskName}"
        elif [ "${#databaseList[@]}" -gt 1 ]; then
            echo "#  database: " >> "${cronPath}/${prefixCronFile}${taskName}"

            local i
            for i in "${databaseList[@]}" ; do
                echo "#    - ${i}" >> "${cronPath}/${prefixCronFile}${taskName}"
            done
        fi

        ;;
    "exclude")
        if [ "${#excludeDatabaseList[@]}" -eq 1 ]; then
            echo "#  exclude-database: ${excludeDatabaseList[0]}" >> "${cronPath}/${prefixCronFile}${taskName}"
        elif [ "${#excludeDatabaseList[@]}" -gt 1 ]; then
            echo "#  exclude-database: " >> "${cronPath}/${prefixCronFile}${taskName}"

            local i
            for i in "${excludeDatabaseList[@]}" ; do
                echo "#    - ${i}" >> "${cronPath}/${prefixCronFile}${taskName}"
            done
        fi
    ;;
    esac

    if [ "${isNonRootUser}" -eq 0 ]; then
        cat >> "${cronPath}/${prefixCronFile}${taskName}" << EOF
${cronFormat} $(whoami) ${sqlBakFile} run ${taskName}
EOF
    elif [ "${isNonRootUser}" -eq 1 ]; then
        cat >> "${cronPath}/${prefixCronFile}${taskName}" << EOF
${cronFormat} ${sqlBakFile} run ${taskName}
EOF
    fi
}

RemoveTask(){
    local taskName="${1}"
    rm -rf "${cronPath:?}/${prefixCronFile}${taskName}"
}

RunTask() {
    local taskName="${1}"
    # 如果文件夹不存在则创建
    if [ ! -d "${backupPath}" ]; then
        mkdir -p "${backupPath}"
    fi
    # 默认备份过程跑在内存中，每次执行指定任务的备份前会清空目录中带该任务名的残留目录
    local topRamPath archiveName needRemoveFolder
    archiveName="${taskName}_-_${todayDateMore}"
    topRamPath="/run/sqlbak"
    mapfile -t needRemoveFolder < <(find "${topRamPath}" -type d -name "*${taskName}*")
    if [[ "${#needRemoveFolder[@]}" -gt 0 ]]; then
        rm -rf "${needRemoveFolder[@]}"
    fi

    # 存在某个任务中指定的所有库都不存在，必须提前跳出此方法，以防生成一个空的备份压缩包
    if [[ "${#finalBackupDatabaseList[@]}" -eq 0 ]]; then
        return
    fi
    mkdir -p "${topRamPath}/${archiveName}"

    # 每个库都备份成一个独立的sql文件，然后将其所在的父级文件夹添加为压缩包，格式：任务名_-_详细日期.tar.gz
    local i commandArrayBase commandArrayTemp characterSet
    commandArrayBase=()
    commandArrayBase+=("${mysqldumpPath}" "-h" "${mysqlIP}" "-P" "${mysqlPort}" "-u" "${mysqlUser}" "-p${mysqlPass}" "-B")
    for i in "${!finalBackupDatabaseList[@]}" ; do
        # 打印
        local currentWidth currentDBNo
        currentDBNo=$((i + 1))
        printf "\r(%d/%d) %s..." "${currentDBNo}" "${#finalBackupDatabaseList[@]}" "正在备份的库名: ${finalBackupDatabaseList[${i}]}"

        # 每个库备份到一个sql文件，每个sql文件名中包含了库名和字符集，格式：库名_-_字符集.sql
        # 每次备份只备份一个库以避免其中有库无法备份导致其他所有库都无法备份成功
        # 备份有问题的写到临时日志（每个库的临时报错日志文件和该任务的汇总报错日志文件）
        commandArrayTemp=()
        characterSet=$("${mysqlPath}" -NB -h"${mysqlIP}" -P"${mysqlPort}" -u"${mysqlUser}" -p"${mysqlPass}" -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '${finalBackupDatabaseList[${i}]}';" 2>/dev/null)
        commandArrayTemp=("${commandArrayBase[@]}" "--default-character-set=${characterSet}" "${finalBackupDatabaseList[${i}]}")
        if ! "${commandArrayTemp[@]}" 2>"${topRamPath}/${archiveName}"/sqlbak_error.tmp 1>"${topRamPath}/${archiveName}/${finalBackupDatabaseList[${i}]}_-_${characterSet}".sql;then
            echo -e "\n出错的库名：${finalBackupDatabaseList[${i}]}" >> "${topRamPath}/${archiveName}"/sqlbak_error.combine
            sed -i '/Using a password on the command line interface can be insecure/d' "${topRamPath}/${archiveName}"/sqlbak_error.tmp
            cat "${topRamPath}/${archiveName}"/sqlbak_error.tmp >> "${topRamPath}/${archiveName}"/sqlbak_error.combine
        fi

        # 因为上面打印名字比较长的话，下一个库名没法将前一个库名完全覆盖，所以进入下个循环前，获取当前打印的字符串的长度，用空格全部覆盖一遍
        currentWidth=$(wc -L <<< "(${currentDBNo}/${#finalBackupDatabaseList[@]}) 正在备份的库名: ${finalBackupDatabaseList[${i}]}...")
        printf "\r%-*s" "${currentWidth}" " "
        unset commandArrayTemp characterSet currentWidth currentDBNo
    done

    # 如果有汇总报错日志文件，则在该任务执行完成后统一写入最终日志，
    if [[ -f "${topRamPath}/${archiveName}"/sqlbak_error.combine ]]; then
        formatError "备份过程中出错，正在写入错误日志..."
        local errorLogFilePath
        errorLogFilePath="${logPath}/error-${todayDateLess}.log"
        WriteLog "${taskName}" "${topRamPath}/${archiveName}"/sqlbak_error.combine "${errorLogFilePath}"
        formatErrorNoBlank "日志已记录,请检查日志：${errorLogFilePath}"
    else
        rm -rf "${topRamPath}/${archiveName}"/sqlbak_error.tmp
    fi

    # 将此任务所在的父级文件夹添加为压缩包，打包后可以删除原始数据了
    pushd "${topRamPath}" >/dev/null 2>&1 || exit 1
        printf "\r%s" "正在生成压缩包..."
        tar -zcPf "${archiveName}".tar.gz "${archiveName}"
        printf "\r%s" "正在转移压缩包到备份目录..."
        mv "${archiveName}".tar.gz "${backupPath}"
        rm -rf "${archiveName}"
        printf "\r%-*s" "$(wc -L <<< '正在转移压缩包到备份目录...')" " "
        printf "\r"
    popd >/dev/null 2>&1 || exit 2
}

WriteLog(){
    local taskName combineLog errorLogFilePath
    taskName="${1}"
    combineLog="${2}"
    errorLogFilePath="${3}"

    cat >> "${errorLogFilePath}" <<EOF
=======================================
时间: $(date +"%Y年%m月%d日 %H:%M:%S")
任务名: ${taskName}

EOF
    cat "${combineLog}" >> "${errorLogFilePath}"
}

DeleteExpiresArchive() {
    local taskName="${1}"
    if [ "${expiresDays}" -eq 0 ]; then
        formatSuccess "任务 ${taskName} 设置为不删除过期备份，跳过"
        return
    fi
    #找出需要删除的备份
    formatInfo "正在清理任务 ${taskName} 的过期备份..."
    local expiredBackupList a
    if [[ ! -d "${backupPath}" ]]; then
        formatWarning "备份路径不存在，无需清理该任务的过期备份"
    else
        mapfile -t -O "${#expiredBackupList}" expiredBackupList < <(find "${backupPath}" -name "${taskName}_-_*.tar.gz" -mtime +"${expiresDays}")
        for a in "${expiredBackupList[@]}"; do
            rm -f "${a}"
        done
        formatSuccess "过期备份清理完成"
    fi
}

Notify() {
    # 0 是删除终端警告
    # 1 是增加终端警告
    # 终端警告只能针对当前用户及同用户的所有登录连接
    local notify="${1}" tmpInfo ptsList=()
    currentUser="$(who -m|awk '{print $1}')"
    tmpInfo="$(who -s|grep -oE "^${currentUser}[ ]+pts/[0-9]+*")"
    mapfile -t -O "${#ptsList[@]}" ptsList < <(cut -d'/' -f2 <<< "${tmpInfo}")
    case "${notify}" in
    0)
        if [ "${isNonRootUser}" -eq 0 ]; then
            rm -rf "${cronPath}/${prefixCronFile}sqlbak-notify.sh"
        elif [ "${isNonRootUser}" -eq 1 ]; then
            rm -rf "${cronPath}/${prefixCronFile}sqlbak-notify.sh"
            RebuildCron
        fi
        rm -rf "${logPath}/notify.sh"
        ;;
    1)
        echo "#!/bin/bash" > "${logPath}/notify.sh"
        for i in "${ptsList[@]}"; do
            cat >> "${logPath}/notify.sh" << EOF
cat > /dev/pts/${i} << BUF

####################################################
sqlbak 工作异常，请立即检查并修正配置文件中的错误
修改完成后请重新测试运行以自动消除此警告

本警告只会扰乱命令行中的正常信息展示
不会将此文字信息追加到正在编辑的命令或文本内容中
请放心保存当前正在编辑的文件
本警告仅限运行备份出现错误时出现，检查、安装操作不会触发
####################################################
BUF
EOF
        done
        chmod +x "${logPath}/notify.sh"
        if [ "${isNonRootUser}" -eq 0 ]; then
            cat >> "${cronPath}/${prefixCronFile}sqlbak-notify.sh" << EOF
* * * * * ${currentUser} ${logPath}/notify.sh
EOF
        elif [ "${isNonRootUser}" -eq 1 ]; then
            cat >> "${cronPath}/${prefixCronFile}sqlbak-notify.sh" << EOF
* * * * * ${logPath}/notify.sh
EOF
        RebuildCron
        fi
        ;;
    esac
}

RebuildCron(){
    formatInfo "正在重建系统定时任务..."
    [ -f "${cronPath}"/final-cron-install-file ] && rm -rf "${cronPath}"/final-cron-install-file
    if [ -n "$(find "${cronPath}" -name "${prefixCronFile}*")" ]; then
        cat "${cronPath}/${prefixCronFile}*" >> "${cronPath}"/final-cron-install-file
    else
        crontab -r >/dev/null 2>&1
    fi
    if [ ! -f "${otherCronFile}" ]; then
        if ! crontab -l >/dev/null 2>&1; then
            touch "${otherCronFile}"
        else
            crontab -l > "${otherCronFile}"
        fi
    else
        cat "${otherCronFile}" >> "${cronPath}"/final-cron-install-file
    fi
    crontab "${cronPath}"/final-cron-install-file >/dev/null 2>&1
    rm -rf "${cronPath}"/final-cron-install-file
    formatSuccess "系统定时任务重建完成"
}

Destroy(){
    formatInfo "正在卸载sqlbak..."
    if [ "${isNonRootUser}" -eq 0 ]; then
        rm -rf "${yamlFile}" \
        "${sqlBakFile}" \
        "${yqFile}" \
        "${logPath}" \
        "${cronPath:?}/${prefixCronFile}*"
    elif [ "${isNonRootUser}" -eq 1 ]; then
        if [ -f "${otherCronFile}" ]; then
            crontab "${otherCronFile}" >/dev/null 2>&1
            formatSuccess "已恢复非本工具生成的用户自定义系统定时计划"
        else
            crontab -r >/dev/null 2>&1
        fi
        rm -rf "${localParentPath}"
    fi
    formatSuccess "sqlbak已卸载，再见"
}

CheckTask(){
    # 判断是否需要删除过期备份
    local fixedExpiresDays
    if [ "${expiresDays}" -eq 0 ]; then
        fixedExpiresDays="永不过期"
    else
        fixedExpiresDays="${expiresDays}"
    fi
    # 判断备份路径是否存在
    if [ ! -d "${backupPath}" ]; then
        formatWarning "备份路径不存在，实际执行时将创建此路径: ${backupPath}"
    fi
    echo -e "${CYAN}
任务名: ${TAN}$1${CYAN}
数据库IP: ${TAN}${mysqlIP}${CYAN}
数据库端口号: ${TAN}${mysqlPort}${CYAN}
数据库用户名: ${TAN}${mysqlUser}${CYAN}
数据库登录密码: ${TAN}${mysqlPass}${CYAN}
备份路径: ${TAN}${backupPath}${CYAN}
过期天数: ${TAN}${fixedExpiresDays}${NORM}"|column -t

    case "${dbType}" in
    "include")
        echo -e "${CYAN}需备份数据库: "
        local k
        for k in "${databaseList[@]}"; do
            echo -e "${TAN}${k}${NORM}"
        done
        ;;
    "exclude")
        echo -e "${CYAN}需排除数据库: "
        local j
        for j in "${excludeDatabaseList[@]}"; do
            echo -e "${TAN}${j}${NORM}"
        done
        ;;
    esac
    echo -e "${CYAN}创建的定时规则: ${TAN}\"${cronFormat}\"${NORM}"
    echo
}

HelpMain(){
    echo -e "
sqlbak  -- mysql/mariadb数据库备份工具

设计思路: 将连接一个数据库所需各参数组合为一个基本单元
通过yaml文件来配置若干基本单元各自的详细信息
一个基本单元被运行时可以备份其中一个或多个数据库
也可以通过安装/卸载以向系统中添加/取消/更新定时备份计划
运行时不限制是否是root用户，工具会自动检测用户并执行对应的功能
"
    if [ "${isClassified}" -eq 0 ]; then
        echo -e "${CYAN}当前系统类型: ${GREEN}常规系统${NORM}
        "
        formatWarning "注意:
1. 本工具首次运行即自动生成模板配置文件
2. 当系统中已存在或未来需要新增其他定时任务的需求时，非root用户必须执行此命令以完成当前用户系统定时重建:
${sqlBakFile} rebuild-cron
3. 未来本工具如有更新，只需手动执行以下命令即可完成功能更新:
${sqlBakFile} update
"
    elif [ "${isClassified}" -eq 1 ]; then
        echo -e "${CYAN}当前系统类型: ${RED}涉密或限制性系统${NORM}
        "
        formatWarning "注意:
1. 对于非root用户使用本工具且系统中已有或未来需要新增其他定时任务的需求，必须执行此命令以完成当前用户系统定时重建:
${sqlBakFile} rebuild-cron
2. 在涉密或其他限制性系统上，此工具的这些选项无法使用(使用时会被主动阻断): update/destroy
"
    fi
formatInfoNoBlank "用法:
"
formatWarningNoBlank "单任务: ${sqlBakFile} [操作] [任务]
多任务: ${sqlBakFile} [操作] [任务1] [任务2] [任务3] ..."
formatInfoNoBlank "
明确操作种类但不知道任务名(功能均为打印帮助菜单，二选一):"
formatWarningNoBlank "
${sqlBakFile} [操作] help
${sqlBakFile} [操作]
"

formatInfoNoBlank "操作种类(选项):"
formatWarningNoBlank "
rebuild-cron 非root用户修改自定义定时任务后手动与已安装数据库备份计划组合重建
update 自动更新本工具正常工作所需依赖
install 指定配置文件中存在的一/多个任务名，安装为系统定时备份计划
remove 指定配置文件中存在的一/多个任务名，删除其已设置的定时备份计划
run 指定配置文件中存在的一/多个任务名，运行其备份操作
check 检查并打印配置文件中的指定一/多个任务的详细配置信息
destroy 彻底卸载本工具并还原非root用户自定义的系统定时
help 打印此帮助菜单并退出
" | column -t
formatInfoNoBlank "检测结果:"
if [ "${isNonRootUser}" -eq 1 ]; then
    formatWarningNoBlank "
当前用户名: $(whoami)
配置文件绝对路径: ${yamlFile}
定时内容路径: ${cronPath}
非root用户增减其他定时任务文件: ${otherCronFile}" | column -t
else
    formatWarningNoBlank "
当前用户名: $(whoami)
定时内容路径: ${cronPath}
当前应用的配置文件: ${yamlFile}
当前应用的yaml解析器: ${yqFile}"| column -t
fi
}
HelpDestroy() {
    :
}
HelpRebuildCron() {
    :
}
HelpUpdate() {
    :
}
HelpInstall() {
    unset i
    local i
    echo
    formatInfoNoBlank "Tips: 支持单个任务安装或多个任务名同时安装，任务名之间用空格隔开
    例1: ${sqlBakFile} install aa
    例2: ${sqlBakFile} install aa bb cc dd ...
    "
    formatInfoNoBlank "特殊任务名:
    all: 全部安装(包括覆盖安装已安装的任务)，后面不能有任何其他任务名
    rest: 仅安装全部未安装的任务，后面不能有任何其他任务名"|column -t
    echo
    formatInfoNoBlank "已安装备份任务如下："
    for i in "${installedTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    echo

    unset i
    local i
    formatInfoNoBlank "未安装备份任务如下："
    for i in "${notInstalledTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    unset i
    echo
}
HelpRemove() {
    unset i
    local i
    echo
    formatInfoNoBlank "Tips: 支持单个任务移除或多个任务名同时移除，任务名之间用空格隔开
例1: ${sqlBakFile} remove aa
例2: ${sqlBakFile} remove aa bb cc dd ...
"
    formatInfoNoBlank "特殊任务名:
all: 全部卸载，后面不能有任何其他任务名"|column -t
    echo
    formatInfoNoBlank "已安装备份任务如下："
    for i in "${installedTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    echo

    unset i
    local i
    formatInfoNoBlank "未安装备份任务如下："
    for i in "${notInstalledTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    unset i
    echo
}
HelpRun() {
    unset i
    local i
    echo
    formatInfoNoBlank "Tips: 支持单个任务备份或多个任务名同时备份，任务名之间用空格隔开
例1: ${sqlBakFile} run aa
例2: ${sqlBakFile} run aa bb cc dd ...

备份出来的压缩包格式: [任务名]_-_[表名]_-_[日期].sql.gz
只要是配置文件中有填写完整信息的任务，无论是否已安装均可执行备份
"
    formatInfoNoBlank "特殊任务名:
all: 全部运行(所有在配置文件中设置的任务)，后面不能有任何其他任务名"|column -t
    echo
    formatInfoNoBlank "已安装备份任务如下："
    for i in "${installedTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    echo

    unset i
    local i
    formatInfoNoBlank "未安装备份任务如下："
    for i in "${notInstalledTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    unset i
    echo
}
HelpCheck() {
    unset i
    local i
    echo
    formatInfoNoBlank "Tips: 支持单个任务查询配置或多个任务名同时查询配置，任务名之间用空格隔开
例1: ${sqlBakFile} check aa
例2: ${sqlBakFile} check aa bb cc dd ...
"
    formatInfoNoBlank "特殊任务名:
all: 查询全部任务的配置细节，后面不能有任何其他任务名"|column -t
    echo
    formatInfoNoBlank "已安装备份任务如下："
    for i in "${installedTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    echo

    unset i
    local i
    formatInfoNoBlank "未安装备份任务如下："
    for i in "${notInstalledTask[@]}" ; do
        formatWarningNoBlank "${i}"
    done
    unset i
    echo
}

# 以上是功能函数
#-----------------------------------
# 以下是流程函数

OperationPreCheck() {
    if [ "${isClassified}" -eq 2 ]; then
        formatError "未知的限制性或涉密系统，请联系作者检查并适配！本工具将不进行任何操作，退出中..."
        exit 1
    fi
    SetConstantAndVariableByCurrentUser
    CheckDependence
}

CheckInputTasks(){
    formatInfo "正在解析输入信息..."
    local wrongTaskName i
    if [ "${#insideSpecifiedTaskList[@]}" -eq 0 ] ||
    [ "${insideSpecifiedTaskList[0]}" == "help" ] ||
    [ "${insideSpecifiedTaskList[0]}" == "all" ] ||
    { [ "${insideSpecifiedTaskList[0]}" == "rest" ] && [ "${firstOption}" == "install" ]; }; then
        return
    fi
    wrongTaskName=()
    for i in "${insideSpecifiedTaskList[@]}" ; do
        if ! printf '%s\0' "${taskList[@]}" | grep -Fxqz -- "${i}"; then
            mapfile -t -O "${#wrongTaskName[@]}" wrongTaskName < <(echo "${i}")
        fi
    done

    if [ "${#wrongTaskName[@]}" -gt 0 ]; then
        formatError "配置文件中不存在以下指定的任务名，请修正并重新运行: "
        for i in "${wrongTaskName[@]}" ; do
            formatWarningNoBlank "${i}"
        done
        exit 1
    fi
    formatSuccess "输入信息解析完成"
}

OperationMain() {
    local insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
    case "${firstOption}" in
        # 无参选项组
        "help"|"-h"|"--help"|"update"|"rebuild-cron"|"destroy")
            if [ -n "${insideSpecifiedTaskList[1]}" ]; then
                formatError "${firstOption} 后面禁止添加其他字段，请删除多余字段后重新运行: ${insideSpecifiedTaskList[*]}"
                exit 1
            else
                OperationNoParam
            fi
            ;;
        # 有参选项组
        "install"|"remove"|"run"|"check")
            formatInfo "正在比对本工具生成的系统定时任务和配置文件中指定的定时任务..."
            CheckInstallStatus
            AutoRepair
            CheckInputTasks
#            echo "specifiedTaskList:"
#            echo "${specifiedTaskList[@]}"
#            echo "insideSpecifiedTaskList:"
#            echo "${insideSpecifiedTaskList[@]}"
#            echo "taskList:"
#            echo "${taskList[@]}"
            OperationExecute "${insideSpecifiedTaskList[@]}"
            ;;
        "")
            formatError "未指定选项，请查看以下帮助菜单"
            HelpMain
            exit 1
            ;;
        *)
            formatError "选项 ${firstOption} 不存在，请查看以下帮助菜单"
            HelpMain
            exit 1
    esac
}

OperationNoParam() {
    case "${firstOption}" in
        "update")
            IsNetworkValid
            if [ "${isClassified}" -eq 0 ] && [ "${networkValid}" -eq 1 ]; then
                formatError "更新功能暂未开放，请等待版本更新，退出中"
    #            CheckUpdate
                exit 0
            else
                formatError "检测到此工具安装在限制性/涉密系统中或无网络连接，更新功能无法使用，退出中"
                exit 1
            fi
            ;;
        "rebuild-cron")
            if [ "${isNonRootUser}" -eq 1 ]; then
                RebuildCron
                exit 0
            elif [ "${isNonRootUser}" -eq 0 ]; then
                formatError "此操作只有非root用户才可以使用，退出中"
                exit 1
            fi
            ;;
        "destroy")
            if [ "${isClassified}" -eq 0 ]; then
                formatError "卸载功能暂未开放，请等待版本更新，退出中"
    #            Destroy
                exit 0
            else
                formatError "检测到此工具安装在限制性/涉密系统中，无法实现自我卸载功能，退出中"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            HelpMain
            exit 0
            ;;
    esac
}

OperationExecute() {
    local insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
    case "${firstOption}" in
        "install")
            OperationInstall "${insideSpecifiedTaskList[@]}"
            ;;
        "update")
            OperationUpdate "${insideSpecifiedTaskList[@]}"
            ;;
        "remove")
            OperationRemove "${insideSpecifiedTaskList[@]}"
            ;;
        "run")
            OperationRun "${insideSpecifiedTaskList[@]}"
            ;;
        "check")
            OperationCheck "${insideSpecifiedTaskList[@]}"
            ;;
    esac
}

OperationInstall() {
#        elif [ "${2}" == "all" ]; then
#            formatInfo "正在安装任务..."
#            for taskName in "${notInstalledTask[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已安装任务名: ${taskName}"
#            done
#            for taskName in "${installedTask[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已更新配置的任务名: ${taskName}"
#            done
#            formatSuccess "任务安装完成"
#        elif [ "${2}" == "rest" ] && [ -z "${3}" ]; then
#            formatInfo "正在安装任务..."
#            if [ "${#notInstalledTask[@]}" -gt 0 ]; then
#                for taskName in "${notInstalledTask[@]}"; do
#                    ParseYaml "${taskName}"
#                    InstallTask "${taskName}"
#                    formatSuccess "已安装任务名: ${taskName}"
#                done
#            elif [ "${#notInstalledTask[@]}" -eq 0 ]; then
#                formatWarning "系统中不存在未安装的任务，跳过安装"
#                exit 0
#            fi
#            formatSuccess "任务安装完成"
#        else
#            formatInfo "正在安装任务..."
#            needInstallTaskList=()
#            alreadyInstallTaskList=()
#            for i in "${specifiedTaskList[@]}" ; do
#                if printf '%s\0' "${installedTask[@]}" | grep -Fxqz -- "${i}"; then
#                    mapfile -t -O "${#alreadyInstallTaskList[@]}" alreadyInstallTaskList < <(echo "${i}")
#                else
#                    mapfile -t -O "${#needInstallTaskList[@]}" needInstallTaskList < <(echo "${i}")
#                fi
#            done
#            for taskName in "${needInstallTaskList[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已安装任务名: ${taskName}"
#            done
#            for taskName in "${alreadyInstallTaskList[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已更新配置的任务名: ${taskName}"
#            done
#            formatSuccess "任务安装完成"
#        fi
#        # 以下是非root用户专用的将最终定时任务安装进系统定时
#        if { [ -n "${2}" ] && [ "${2}" != "help" ]; } && [ "${isNonRootUser}" -eq 1 ]; then
#            RebuildCron
#        fi
    local taskName commonList insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
    commonList=()
    if [ -n "${insideSpecifiedTaskList[1]}" ]; then
        case "${insideSpecifiedTaskList[0]}" in
            "all"|"help"|"rest")
                formatError "${insideSpecifiedTaskList[0]} 后面禁止添加其他字段，请删除多余字段后重新运行: ${insideSpecifiedTaskList[*]:1}"
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    else
        case "${insideSpecifiedTaskList[0]}" in
            "all")
                commonList=("${taskList[@]}")
                ;;
            "rest")
                commonList=("${notInstalledTask[@]}")
                ;;
            "help")
                HelpInstall
                exit 0
                ;;
            "")
                formatError "未指定选项，请查看以下帮助菜单"
                HelpInstall
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    fi
    formatInfo "正在安装任务..."
    if [ "${#commonList[@]}" -eq 0 ]; then
        formatWarning "系统中不存在未安装的任务，跳过安装"
        return
    fi
    if [ "${#notInstalledTask[@]}" -gt 0 ]; then
        for taskName in "${commonList[@]}"; do
            ParseYaml "${taskName}"
            InstallTask "${taskName}"
            formatSuccess "已安装任务名: ${taskName}"
        done
    fi

    needInstallTaskList=()
    alreadyInstallTaskList=()
    for i in "${commonList[@]}" ; do
        if printf '%s\0' "${installedTask[@]}" | grep -Fxqz -- "${i}"; then
            mapfile -t -O "${#alreadyInstallTaskList[@]}" alreadyInstallTaskList < <(echo "${i}")
        else
            mapfile -t -O "${#needInstallTaskList[@]}" needInstallTaskList < <(echo "${i}")
        fi
    done
    for taskName in "${needInstallTaskList[@]}"; do
        ParseYaml "${taskName}"
        InstallTask "${taskName}"
        formatSuccess "已安装任务名: ${taskName}"
    done
    for taskName in "${alreadyInstallTaskList[@]}"; do
        ParseYaml "${taskName}"
        InstallTask "${taskName}"
        formatSuccess "已更新配置的任务名: ${taskName}"
    done



    for taskName in "${commonList[@]}"; do
        echo -e "${CYAN}正在检查合规性的任务：${TAN}${taskName}${NORM}"
        ParseYaml "${taskName}"
        if [[ "${#wrongDatabaseList[@]}" -gt 0 ]]; then
            formatWarning "检查完成但存在错误"
        else
            formatSuccess "检查通过"
        fi
        CheckTask "${taskName}"
    done
}

OperationUpdate() {
#        elif [ "${2}" == "all" ]; then
#            formatInfo "正在安装任务..."
#            for taskName in "${notInstalledTask[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已安装任务名: ${taskName}"
#            done
#            for taskName in "${installedTask[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已更新配置的任务名: ${taskName}"
#            done
#            formatSuccess "任务安装完成"
#        elif [ "${2}" == "rest" ] && [ -z "${3}" ]; then
#            formatInfo "正在安装任务..."
#            if [ "${#notInstalledTask[@]}" -gt 0 ]; then
#                for taskName in "${notInstalledTask[@]}"; do
#                    ParseYaml "${taskName}"
#                    InstallTask "${taskName}"
#                    formatSuccess "已安装任务名: ${taskName}"
#                done
#            elif [ "${#notInstalledTask[@]}" -eq 0 ]; then
#                formatWarning "系统中不存在未安装的任务，跳过安装"
#                exit 0
#            fi
#            formatSuccess "任务安装完成"
#        else
#            formatInfo "正在安装任务..."
#            needInstallTaskList=()
#            alreadyInstallTaskList=()
#            for i in "${specifiedTaskList[@]}" ; do
#                if printf '%s\0' "${installedTask[@]}" | grep -Fxqz -- "${i}"; then
#                    mapfile -t -O "${#alreadyInstallTaskList[@]}" alreadyInstallTaskList < <(echo "${i}")
#                else
#                    mapfile -t -O "${#needInstallTaskList[@]}" needInstallTaskList < <(echo "${i}")
#                fi
#            done
#            for taskName in "${needInstallTaskList[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已安装任务名: ${taskName}"
#            done
#            for taskName in "${alreadyInstallTaskList[@]}"; do
#                ParseYaml "${taskName}"
#                InstallTask "${taskName}"
#                formatSuccess "已更新配置的任务名: ${taskName}"
#            done
#            formatSuccess "任务安装完成"
#        fi
#        # 以下是非root用户专用的将最终定时任务安装进系统定时
#        if { [ -n "${2}" ] && [ "${2}" != "help" ]; } && [ "${isNonRootUser}" -eq 1 ]; then
#            RebuildCron
#        fi
    local taskName commonList insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
    commonList=()
    if [ -n "${insideSpecifiedTaskList[1]}" ]; then
        case "${insideSpecifiedTaskList[0]}" in
            "all"|"help"|"rest")
                formatError "${insideSpecifiedTaskList[0]} 后面禁止添加其他字段，请删除多余字段后重新运行: ${insideSpecifiedTaskList[*]:1}"
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    else
        case "${insideSpecifiedTaskList[0]}" in
            "all")
                commonList=("${taskList[@]}")
                ;;
            "rest")
                commonList=("${taskList[@]}")
                ;;
            "help")
                HelpInstall
                exit 0
                ;;
            "")
                formatError "未指定选项，请查看以下帮助菜单"
                HelpInstall
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    fi
    formatInfo "正在安装任务..."
    for taskName in "${needInstallTaskList[@]}"; do
        ParseYaml "${taskName}"
        InstallTask "${taskName}"
        formatSuccess "已安装任务名: ${taskName}"
    done
    for taskName in "${alreadyInstallTaskList[@]}"; do
        ParseYaml "${taskName}"
        InstallTask "${taskName}"
        formatSuccess "已更新配置的任务名: ${taskName}"
    done
    for taskName in "${commonList[@]}"; do
        echo -e "${CYAN}正在检查合规性的任务：${TAN}${taskName}${NORM}"
        ParseYaml "${taskName}"
        if [[ "${#wrongDatabaseList[@]}" -gt 0 ]]; then
            formatWarning "检查完成但存在错误"
        else
            formatSuccess "检查通过"
        fi
        CheckTask "${taskName}"
    done
}

OperationRemove() {
    local insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
        if [ "${insideSpecifiedTaskList[0]}" == "all" ] && [ -z "${insideSpecifiedTaskList[1]}" ]; then
            formatInfo "正在卸载任务..."
            if [ "${#installedTask[@]}" -gt 0 ]; then
                for taskName in "${installedTask[@]}"; do
                    ParseYaml "${taskName}"
                    RemoveTask "${taskName}"
                    formatSuccess "已卸载任务名: ${taskName}"
                done
                formatSuccess "任务卸载完成"
            elif [ "${#installedTask[@]}" -eq 0 ]; then
                formatWarning "系统中不存在已安装的任务，跳过卸载"
                exit 1
            fi
        else
            needRemoveTaskList=()
            alreadyRemovedTaskList=()
            for i in "${specifiedTaskList[@]}" ; do
                if printf '%s\0' "${installedTask[@]}" | grep -Fxqz -- "${i}"; then
                    mapfile -t -O "${#needRemoveTaskList[@]}" needRemoveTaskList < <(echo "${i}")
                else
                    mapfile -t -O "${#alreadyRemovedTaskList[@]}" alreadyRemovedTaskList < <(echo "${i}")
                fi
            done
            if [ "${#needRemoveTaskList[@]}" -gt 0 ]; then
                formatInfo "正在卸载任务..."
                for taskName in "${needRemoveTaskList[@]}"; do
                    ParseYaml "${taskName}"
                    RemoveTask "${taskName}"
                    formatSuccess "已卸载任务名: ${taskName}"
                done
                if [ "${#alreadyRemovedTaskList[@]}" -gt 0 ]; then
                    formatWarning "以下任务当前并未安装，无需在卸载时指定，卸载时将跳过:"
                    for i in "${alreadyRemovedTaskList[@]}" ; do
                        formatWarningNoBlank "${i}"
                    done
                fi
                formatSuccess "任务卸载完成"
            else
                formatWarning "所有指定的任务均未安装，跳过卸载"
                exit 1
            fi
        fi
#        # 以下是非root用户专用的将最终定时任务安装进系统定时
#        if { [ -n "${2}" ] && [ "${2}" != "help" ]; } && [ "${isNonRootUser}" -eq 1 ]; then
#            RebuildCron
#        fi
    local taskName commonList
    commonList=()
    if [ -n "${insideSpecifiedTaskList[1]}" ]; then
        case "${insideSpecifiedTaskList[0]}" in
            "all"|"help")
                formatError "${insideSpecifiedTaskList[0]} 后面禁止添加其他字段，请删除多余字段后重新运行: ${insideSpecifiedTaskList[*]:1}"
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    else
        case "${insideSpecifiedTaskList[0]}" in
            "all")
                commonList=("${taskList[@]}")
                ;;
            "help")
                HelpRemove
                exit 0
                ;;
            "")
                formatError "未指定参数，请查看以下帮助菜单"
                HelpRemove
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    fi
    formatInfo "正在依次检查并展示任务配置..."
    for taskName in "${commonList[@]}"; do
        printf "=====================\n"
        echo -e "${CYAN}正在检查合规性的任务：${TAN}${taskName}${NORM}"
        ParseYaml "${taskName}"
        if [[ "${#wrongDatabaseList[@]}" -gt 0 ]]; then
            formatWarning "检查完成但存在错误"
        else
            formatSuccess "检查通过"
        fi
        CheckTask "${taskName}"
    done
}

OperationRun() {
    local taskName commonList insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
    commonList=()
    if [ -n "${insideSpecifiedTaskList[1]}" ]; then
        case "${insideSpecifiedTaskList[0]}" in
            "all"|"help")
                formatError "${insideSpecifiedTaskList[0]} 后面禁止添加其他字段，请删除多余字段后重新运行: ${insideSpecifiedTaskList[*]:1}"
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    else
        case "${insideSpecifiedTaskList[0]}" in
            "all")
                commonList=("${taskList[@]}")
                ;;
            "help")
                HelpRun
                exit 0
                ;;
            "")
                formatError "未指定参数，请查看以下帮助菜单"
                HelpRun
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    fi
    formatInfo "正在执行备份任务..."
    local flag
    flag=1
    for taskName in "${commonList[@]}"; do
        printf "=====================\n"
        echo -e "${CYAN}正在执行备份的任务：${TAN}${taskName}${NORM}"
        ParseYaml "${taskName}"
        if [[ -n "${wrongTaskList}" ]]; then
            formatWarning "${taskName} 任务无法连接，已跳过该任务的备份"
            flag=1
        else
            RunTask "${taskName}"
            if [[ "${#wrongDatabaseList[@]}" -gt 0 ]]; then
                flag=1
                formatWarning "任务 ${taskName} 备份结束，但跳过了配置文件中已指定但实际不存在的数据库:"
                printf "%s\n" "${wrongDatabaseList[@]}"
            else
                formatSuccess "已备份 ${taskName} 任务中指定的全部数据库"
            fi
        fi
        DeleteExpiresArchive "${taskName}"
    done
    # 增减警告(正常开发调试操作不会在涉密环境中使用，故哪怕存在警告也不在命令行中打印)
    if [[ "${isClassified}" -eq 0 ]]; then
        case "${flag}" in
        0)
            Notify 0
            ;;
        1)
            Notify 1
            ;;
        *)
        esac
    fi
}

OperationCheck() {
    local taskName commonList insideSpecifiedTaskList=()
    insideSpecifiedTaskList=("${@}")
    commonList=()
    if [ -n "${insideSpecifiedTaskList[1]}" ]; then
        case "${insideSpecifiedTaskList[0]}" in
            "all"|"help")
                formatError "${insideSpecifiedTaskList[0]} 后面禁止添加其他字段，请删除多余字段后重新运行: ${insideSpecifiedTaskList[*]:1}"
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    else
        case "${insideSpecifiedTaskList[0]}" in
            "all")
                commonList=("${taskList[@]}")
                ;;
            "help")
                HelpCheck
                exit 0
                ;;
            "")
                formatError "未指定参数，请查看以下帮助菜单"
                HelpCheck
                exit 1
                ;;
            *)
                commonList=("${insideSpecifiedTaskList[@]}")
        esac
    fi
    formatInfo "正在依次检查并展示任务配置..."
    for taskName in "${commonList[@]}"; do
        printf "=====================\n"
        echo -e "${CYAN}正在检查合规性的任务：${TAN}${taskName}${NORM}"
        ParseYaml "${taskName}"
        if [[ "${#wrongDatabaseList[@]}" -gt 0 ]] || [[ -n "${wrongTaskList}" ]]; then
            formatWarning "检查完成但存在错误"
        else
            formatSuccess "检查通过"
        fi
        CheckTask "${taskName}"
    done
}

# 主程序入口
OperationPreCheck
# 判断工具后跟的首个参数名以分配不同功能
firstOption="${1}"
specifiedTaskList=("${@:2}")
OperationMain "${specifiedTaskList[@]}"

##############################################################################################################################
# 以下是暂时未启用的功能对应的功能模块或暂时弃用的逻辑代码
# 变量初始化
#remoteYQLatestHTML=
#
#dirPath=
#localYQ=
#CheckRateLimitDeprecated(){
#    # github有调用API的频率限制，必须先检测
#    # https://docs.github.com/en/rest/overview/resources-in-the-rest-api?apiVersion=2022-11-28#rate-limiting
#    formatInfo "正在检查外网连接情况..."
#    if timeout 5s ping -c2 -W1 www.baidu.com > /dev/null 2>&1; then
#        formatInfo "正在检查 github API 调用限制信息..."
#        local githubGetRateInfo postLimit postRemaining
#        githubGetRateInfo=$(curl -s https://api.github.com/rate_limit|xargs|grep -o "rate: {.*.}"|sed 's/,/\n/g; s/{/\n/g; s/}/\n/g; s/ \+//g')
#        postLimit=$(echo "${githubGetRateInfo}" | awk -F ':' /^limit/'{print $2}')
#        postRemaining=$(echo "${githubGetRateInfo}" | awk -F ':' /^remaining/'{print $2}')
#        formatSuccessNoBlank "GitHub 调用速率为 ${postLimit} 次/小时"
#        if [ "${postRemaining}" -eq 0 ]; then
#            formatError "$(date +%Y年%m月%d日%k:00) 至 $(date +%Y年%m月%d日%k:00 -d "+1 hour") 时间段内剩余可可查询升级的次数为 ${postRemaining}，请过一小时再尝试升级，退出中"
#            exit 1
#        elif [ "${postRemaining}" -lt 10 ]; then
#            formatErrorNoBlank "$(date +%Y年%m月%d日%k:00) 至 $(date +%Y年%m月%d日%k:00 -d "+1 hour") 时间段内剩余可查询升级的次数还剩 ${postRemaining} 次"
#        else
#            formatInfoNoBlank "$(date +%Y年%m月%d日%k:00) 至 $(date +%Y年%m月%d日%k:00 -d "+1 hour") 时间段内剩余可可查询升级的次数还剩 ${postRemaining} 次"
#        fi
#        remoteYQLatestHTML="$(curl -s --max-time 15 https://api.github.com/repos/mikefarah/yq/releases/latest)"
#        if [ -z "${remoteYQLatestHTML}" ]; then
#            formatError "获取 GitHub API 失败，与 GitHub 连接可能存在问题，请过一会再尝试"
#            exit 1
#        fi
#    else
#	    formatError "网络不通，请检查网络，退出中"
#	    exit 1
#    fi
#}
#CheckUpdateDeprecated(){
#    # 未来更新到网络上再在此模块中添加远程更新sqlbak的方法
#    CheckRateLimit
#    formatInfo "正在解析yq最新版本号并比对本地yq版本(如果存在)..."
#    local remoteYQVersion localYQVersion
#    remoteYQVersion=$(echo "${remoteYQLatestHTML}"|grep -o "tag_name.*.\""|awk -F '"' '{print $(NF-1)}')
#    if [ -f "${yqFile}" ]; then
#        if [ ! -x "${yqFile}" ]; then
#            chmod +x "${yqFile}"
#        fi
#        localYQVersion=$(${yqFile} -V|awk '{print $NF}')
#        if [[ ! "${remoteYQVersion}" == "${localYQVersion}" ]]; then
#            formatWarning "发现新版本yq，正在更新..."
#            DownloadYQ
#        else
#            formatSuccess "yq已是最新版本，无需更新，跳过"
#        fi
#    else
#        formatWarning "系统不存在必要解析工具，将检查依赖并试图修复工作环境，修复后请重新运行本工具"
#        CheckDependence "skip"
#        exit 0
#    fi
#}
#DownloadYQDeprecated() {
#    local yqDownloadLink yqRemoteSize yqLocalSize
#	yqDownloadLink=$(echo "${remoteYQLatestHTML}" | grep "browser_download_url.*.yq_linux_amd64\"" | awk -F '[" ]' '{print $(NF-1)}')
#	yqRemoteSize=$(echo "${remoteYQLatestHTML}" | grep -B 10 "browser_download_url.*.yq_linux_amd64\"" | grep size | awk -F '[ ,]' '{print $(NF-1)}')
#	if [ -z "${yqDownloadLink}" ]; then
#	    formatError "无法获取下载链接，请检查网络，退出中"
#	    exit 1
#	else
#	    formatInfo "正在下载并放置yq到系统中..."
#	    formatWarningNoBlank "下载链接: ${yqDownloadLink}"
#	    if [ -f "${yqFile}.tmp" ]; then
#	        formatWarning "发现上次运行时的下载残留，正在清理..."
#	        rm -rf "${yqFile}.tmp"
#	    fi
#
#	    if ! curl -L -o "${yqFile}.tmp" "${yqDownloadLink}"; then
#	        formatError "下载失败，请重新运行脚本尝试下载"
#	        formatError "清理下载残留，退出中"
#	        rm -rf "${yqFile}.tmp"
#	        exit 1
#	    else
#	        formatInfo "正在校验完整性..."
#	        yqLocalSize=$(stat --printf="%s" "${yqFile}.tmp")
#	        if [ "${yqLocalSize}" == "${yqRemoteSize}" ]; then
#	            mv -f "${yqFile}.tmp" "${yqFile}"
#	            chmod +x "${yqFile}"
#	            formatSuccess "完整性校验通过，下载并更新完成"
#	        else
#	            formatError "下载版本和远程版本大小不一致，请重新运行脚本以尝试修正此问题，退出中"
#	            rm -rf "${yqFile}.tmp"
#	            exit 1
#	        fi
#	    fi
#	fi
#}
#CheckDependenceDeprecated(){
#    # 这是模块内的部分代码，暂时弃用，不要直接取消注释，部分变量已经被删
#    if [ ! -f "${yqFile}" ]; then
#	    if [ "${isClassified}" -eq 0 ]; then
#            if [ "${1}" == "skip" ]; then
#                :
#            else
#                CheckRateLimit
#            fi
#            if [ -f "${localYQ}" ]; then
#                [ ! -x "${localYQ}" ] && chmod +x "${localYQ}"
#                if "${localYQ}" -V|awk '{print $NF}' >/dev/null 2>&1; then
#                    formatSuccess "系统不存在必要解析工具但本地存在，已处理并安装进系统"
#                    cp -a "${localYQ}" "${binPath}"
#                else
#                    formatWarning "系统不存在必要解析工具，本地存在的工具已损坏，正在下载yq，若下载过慢可通过组合键CTRL+C中断工具运行"
#                    formatWarning "之后手动下载并改名成yq放在此处(${dirPath})，系统会自动检测可用性，确认无误将自动安装进系统以跳过下载过程"
#                    rm -rf "${localYQ}"
#                    DownloadYQ
#                fi
#            else
#                formatWarning "系统和本工具同目录均不存在yq，正在下载yq，若下载过慢可通过组合键CTRL+C中断工具运行"
#                formatWarning "之后手动下载并改名成yq放在此处(${dirPath})，系统会自动检测可用性，确认无误将自动安装进系统以跳过下载过程"
#                DownloadYQ
#            fi
#        else
#            formatError "解析工具yq不存在，程序不会进行任何操作，退出中"
#            exit 1
#        fi
#    fi
#	if [ "${isClassified}" -eq 0 ]; then
#    # 这里这个本地自动覆盖的方式继续保留，未来更新到网络上再在update模块中添加远程更新的方法
#        if [ "${sqlBakFile}" != "$(readlink -f "$0")" ]; then
#            formatInfo "正在更新 sqlbak..."
#            cp -af "$(readlink -f "$0")" "${sqlBakFile}"
#            chmod +x "${sqlBakFile}"
#            formatSuccess "sqlbak 更新成功"
#        fi
#    fi
#
#}