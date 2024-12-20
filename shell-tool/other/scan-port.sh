#!/bin/bash
toolNameDefault="scan-port"
toolNameAutoGet=$(readlink -f "$0")
currentDateTime="$(date +"%Y-%m-%d_%H-%M-%S")"
defaultLogFileNamePrefix="scan-result_"
defaultLogFileNameSuffix=".log"
longLogFilePath=
shortLogFilePath=
isClassified=

ssExists=0
netstatExists=0
lsofExists=0
ncExists=0
telnetExists=0

logDirPath=
needCreatePath=
targetIP=
defaultTargetIP=127.0.0.1
scanPlan=

# 终端色彩
if ! which tput >/dev/null 2>&1; then
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

IsClassifiedSystem(){
    # 0 = 否
    # 1 = 是
    # 2 = 暂未见过的涉密系统
    formatInfo "正在检测系统是否涉密..."
    echo "date" > /tmp/test_classified.sh
    if ! bash /tmp/test_classified.sh >/dev/null 2>&1; then
        if bash <(cat /tmp/test_classified.sh) >/dev/null 2>&1; then
            isClassified=1
            formatSuccess "系统涉密"
        else
            isClassified=2
            formatError "未知涉密系统，暂未适配，退出中"
            exit 1
        fi
    else
        isClassified=0
        formatSuccess "系统非涉密"
    fi
    rm -rf /tmp/test_classified.sh
}

InnerHelp(){
    InnerHelpClassified(){
        echo -e "例：
场景 1：检测非本工具所在节点的端口可访问性
命令：
${toolNameDefault} -l /var/log/${toolNameDefault} -i 1.1.1.1

场景 2：检测本工具所在节点被占用端口的进程信息
命令（效果相同，选任一执行）：
${toolNameDefault} -l /var/log/${toolNameDefault} -i localhost
${toolNameDefault} -l /var/log/${toolNameDefault} -i 127.0.0.1
${toolNameDefault} -l /var/log/${toolNameDefault}
"
    formatWarning "涉密系统中运行本工具时无法自动获取必要路径，因此必须指定将日志文件保存到的文件夹所对应的绝对路径"
    }
    InnerHelpNormal(){
        echo -e "例：
场景 1：检测非本工具所在节点的端口可访问性
命令（效果相同，选任一执行）：
${toolNameAutoGet} -i 1.1.1.1 -l /var/log/${toolNameDefault}
${toolNameAutoGet} -i 1.1.1.1

场景 2：检测本工具所在节点被占用端口的进程信息
命令（效果相同，选任一执行）：
${toolNameAutoGet} -i localhost
${toolNameAutoGet} -i 127.0.0.1
${toolNameAutoGet} -i localhost -l /var/log/${toolNameDefault}
${toolNameAutoGet} -i 127.0.0.1 -l /var/log/${toolNameDefault}
${toolNameAutoGet} -l /var/log/${toolNameDefault}

场景 3：场景 3：查看本帮助菜单并退出
命令（效果相同，选任一执行）：
${toolNameDefault} -h
${toolNameDefault} --help
"
    formatWarning "在常规系统中，如果运行本工具时没有指定将日志文件保存到的文件夹所对应的绝对路径，则会自动生成到终端执行此工具时所在的路径下，例："
    formatWarningNoBlank "先 cd 到任意路径下然后执行本工具且参数不写日志所在文件夹的绝对路径：" \
    "cd /run" \
    "执行本工具时不指定将日志文件保存到的文件夹所对应的绝对路径参数时，自动生成的日志可以在此路径下找到：" \
    "/run/${defaultLogFileNamePrefix}$(date +"%Y-%m-%d_%H-%M-%S")${defaultLogFileNameSuffix}"
    }

    echo -e "【端口扫描工具】

本工具有两种功能：
1. 检测可访问网段内的目标节点的端口可访问性（前提：防火墙放行端口 + 端口对应服务正在运行）
2. 扫描本机端口（用途：端口对应的服务是否启动 & 占用此端口的是什么服务）
"
    echo -e "可用选项：
-i|--ip 指定IP地址
-l|--log 将日志文件保存到的文件夹所对应的绝对路径
-h|--help 打印此帮助菜单并退出" | column -t | sed 's#|# | #g'

    echo -e "
Tip: 长短选项随意组合，以下这些同时指定了 IP 和日志路径的写法均等效：
-i [IP地址] -l [日志所在文件夹的绝对路径]
-i [IP地址] --log [日志所在文件夹的绝对路径]
--ip [IP地址] -l [日志所在文件夹的绝对路径]
--ip [IP地址] --log [日志所在文件夹的绝对路径]
"

    if [ "${isClassified}" -eq 0 ]; then
        echo -e "${CYAN}当前系统类型: ${GREEN}常规系统${NORM}
        "
        InnerHelpNormal
    elif [ "${isClassified}" -eq 1 ]; then
        echo -e "${CYAN}当前系统类型: ${RED}涉密或限制性系统${NORM}
        "
        InnerHelpClassified
    fi

    exit 1
}

TestRoot() {
    formatInfo "正在检测当前用户是否为 root..."
	if [ $EUID -ne 0 ] || [[ $(grep -o "^$(whoami):.*" /etc/passwd | cut -d':' -f3) != 0 ]]; then
        formatError "请切换到 root 用户再重新运行，退出中"
		exit 1
	fi
	formatSuccess "检测通过，当前用户为 root"
}

ParseOption(){
    formatInfo "正在检测选项和参数的可用性..."
    # 如果没有指定ip或指定的ip是localhost或127.0.0.1，则默认扫本地所有端口以记录可访问端口是什么服务占用了
    # 如果指定了ip且不是localhost或127.0.0.1，则检测远程端口可访性
    case "${targetIP}" in
    ""|"127.0.0.1"|"localhost")
        scanPlan="local"
        if [[ -z "${targetIP}" ]]; then
            targetIP="${defaultTargetIP}"
        fi
        ;;
    *:*)
        formatError "暂未适配IPV6，请指定IPV4地址，退出中"
        exit 1
        ;;
    *)
        if [[ ! "${targetIP}" =~ ^(([1-9]|[1-9][0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5]))\.(([1-9]?[0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5]))\.){2}([1-9]?[0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5])))$ ]]; then
            formatError "IPV4地址不合法，请修改，退出中"
            exit 1
        fi
        scanPlan="remote"
        ;;
    esac

    local parentPath flag
    case "${isClassified}" in
    0)
        if [[ -z "${logDirPath}" ]]; then
            logDirPath=$(dirname "${toolNameAutoGet}")
            longLogFilePath="${logDirPath}/${defaultLogFileNamePrefix}_${scanPlan}_${targetIP}_all_${currentDateTime}.${defaultLogFileNameSuffix}"
            shortLogFilePath="${logDirPath}/${defaultLogFileNamePrefix}_${scanPlan}_${targetIP}_short_${currentDateTime}.${defaultLogFileNameSuffix}"
        fi
        ;;
    1)
        if [[ -z "${logDirPath}" ]]; then
            formatError "涉密系统中将日志文件保存到的文件夹所对应的绝对路径不能为空，退出中"
            exit 1
        fi
        ;;
    esac

    if [[ ! "${logDirPath}" =~ ^/ ]]; then
        formatError "禁止使用相对路径，请修改，退出中"
        exit 1
    elif [[ "${logDirPath}" == "/" ]]; then
        formatError "禁止使用系统根目录 / 作为日志的绝对路径，请修改，退出中"
        exit 1
    elif [[ -f "${logDirPath}" ]]; then
        formatError "指定的必须是将日志文件保存到的文件夹所对应的绝对路径，而不是要生成的日志的文件绝对路径"
        formatError "指定的绝对路径存在且是个文件，请检查，退出中"
        exit 1
    elif [[ -d "${logDirPath}" ]]; then
        formatWarning "指定的日志绝对路径已存在，扫描时将直接使用"
    fi

    parentPath="${logDirPath}"
    flag=0
    while true; do
        if [[ "${parentPath}" == "/" ]]; then
            break
        fi
        if [[ ! -e "${parentPath}" ]]; then
            parentPath="$(dirname "${parentPath}")"
            flag=$(( flag + 1 ))
            continue
        fi
        if [[ -f "${parentPath}" ]]; then
            formatError "指定的日志绝对路径中有一级父级路径本身是文件而非目录，"
            formatError "有问题的父级目录: ${parentPath}"
            formatError "请修改，退出中"
            exit 1
        elif [[ -d "${parentPath}" ]]; then
            if ! touch "${parentPath}"/testfile >/dev/null 2>&1; then
                formatError "此路径无写入权限，无法作为生成日志的路径: ${parentPath}"
                formatError "退出中"
                exit 1
            fi
            rm -rf "${parentPath}"/testfile
            if [[ "${flag}" -ne 0 ]]; then
                needCreatePath=1
            else
                needCreatePath=0
            fi
            break
        fi
    done
    formatSuccess "选项和参数的可用性检测通过"
}

TestDependence(){
    formatInfo "正在检查本工具功能的依赖性..."
    local dependencyGroup="${1}"
    InnerTestDependenceLocal(){
        which ss >/dev/null 2>&1 && ssExists=1
        which lsof >/dev/null 2>&1 && lsofExists=1
        which netstat >/dev/null 2>&1 && netstatExists=1
        if [[ "${ssExists}" -eq 0 ]] && [[ "${lsofExists}" -eq 0 ]] && [[ "${netstatExists}" -eq 0 ]]; then
            formatError "本工具本机检测进程功能无法使用，请自行安装以下至少一个所依赖的软件后重新运行："
            formatError "ss / lsof / netstat"
            formatError "退出中"
            exit 1
        fi
    }
    InnerTestDependenceRemote(){
        which nc >/dev/null 2>&1 && ncExists=1
        which telnet >/dev/null 2>&1 && telnetExists=1
        if [[ "${ncExists}" -eq 0 ]] && [[ "${telnetExists}" -eq 0 ]]; then
            formatError "本工具远程检测防火墙功能无法使用，请自行安装以下至少一个所依赖的软件后重新运行："
            formatError "nc / telnet"
            formatError "退出中"
            exit 1
        fi
    }

    case "${dependencyGroup}" in
    "local")
        InnerTestDependenceLocal
        ;;
    "remote")
        InnerTestDependenceRemote
        ;;
    esac
    formatSuccess "本工具功能的依赖性检测通过"
}

Scan(){
    local scanGroup="${1}"
    if [[ "${needCreatePath}" -eq 1 ]]; then
        mkdir -p "$(dirname "${logDirPath}")"
    elif [[ -f "${logDirPath}" ]]; then
        # shellcheck disable=SC2188
        > "${logDirPath}"
    fi
    InnerScanLocal(){
        :
    }
    InnerScanRemote(){
        echo -e "【扫描IP：${targetIP}】\n" > "${logDirPath}"
        echo "==============================================" >> "${logDirPath}"
        for i in {1..65535}; do
            printf '\r总数: %d / 检测端口号: %d' "65535" "${i}"
            local timeoutSecond=10 finalDiagnosisResult

            if [[ "${ncExists}" -eq 1 ]]; then
                local ncOutput ncFlag=0 ncDiagnosisResult
                ncOutput=$(stdbuf -oL -eL timeout "${timeoutSecond}" nc -zv "${targetIP}" "${i}" 2>&1)
                # 防火墙没放行
                if [[ "${ncOutput}" =~ "No route to host" ]]; then
                    ncFlag=$(( ncFlag + 4 ))
                fi
                # 防火墙已放行，但没有进程占用该端口
                if [[ "${ncOutput}" =~ "Connection refused" ]]; then
                    ncFlag=$(( ncFlag + 2 ))
                fi
                # 防火墙放行且该端口有进程在用
                if [[ "${ncOutput}" =~ "Connected to" ]]; then
                    ncFlag=$(( ncFlag + 1 ))
                fi

                if [[ "${ncFlag}" -eq 4 ]]; then
                    ncDiagnosisResult="防火墙没放行"
                elif [[ "${ncFlag}" -eq 2 ]]; then
                    ncDiagnosisResult="防火墙已放行，但没有进程占用该端口"
                elif [[ "${ncFlag}" -eq 1 ]]; then
                    ncDiagnosisResult="防火墙放行且该端口有进程在用"
                else
                    ncDiagnosisResult="异常情况，请根据输出结果自行判断"
                fi
            fi
            if [[ "${telnetExists}" -eq 1 ]]; then
                local telnetOutput telnetFlag=0 telnetDiagnosisResult
                telnetOutput=$(stdbuf -oL -eL timeout "${timeoutSecond}" telnet "${targetIP}" "${i}" 2>&1)
                # 防火墙没放行
                if [[ "${telnetOutput}" =~ "No route to host" ]]; then
                    telnetFlag=$(( telnetFlag + 4 ))
                fi
                # 防火墙已放行，但没有进程占用该端口
                if [[ "${telnetOutput}" =~ "Connection refused" ]]; then
                    telnetFlag=$(( telnetFlag + 2 ))
                fi
                # 防火墙放行且该端口有进程在用
                if [[ "${telnetOutput}" =~ "Connected to" ]]; then
                    telnetFlag=$(( telnetFlag + 1 ))
                fi

                if [[ "${telnetFlag}" -eq 4 ]]; then
                    telnetDiagnosisResult="防火墙没放行"
                elif [[ "${telnetFlag}" -eq 2 ]]; then
                    telnetDiagnosisResult="防火墙已放行，但没有进程占用该端口"
                elif [[ "${telnetFlag}" -eq 1 ]]; then
                    telnetDiagnosisResult="防火墙放行且该端口有进程在用"
                else
                    telnetDiagnosisResult="异常情况，请根据输出结果自行判断"
                fi
            fi
            if [[ "${ncExists}" -eq 1 ]] && [[ "${telnetExists}" -eq 1 ]]; then
                if [[ "${ncDiagnosisResult}" == "${telnetDiagnosisResult}" ]]; then
                    finalDiagnosisResult="${ncDiagnosisResult}"
                else
                    finalDiagnosisResult="异常情况，请根据输出结果自行判断"
                fi
            elif [[ "${ncExists}" -eq 1 ]]; then
                finalDiagnosisResult="${ncDiagnosisResult}"
            elif [[ "${telnetExists}" -eq 1 ]]; then
                finalDiagnosisResult="${telnetDiagnosisResult}"
            fi
            echo ""
#            unset timeoutSecond ncOutput telnetOutput ncFlag telnetFlag ncDiagnosisResult telnetDiagnosisResult finalDiagnosisResult
        done
    }

    case "${scanGroup}" in
    "local")
        formatInfo "正在扫描本机端口占用情况..."
        InnerScanLocal
        ;;
    "remote")
        formatInfo "正在扫描指定 IP 的防火墙放行情况..."
        InnerScanRemote
        ;;
    esac

    echo
    formatSuccess "扫描结束，请检查生成日志："
    echo "${logDirPath}"

#            if [[ "${ssExists}" -eq 1 ]]; then
#                echo "ss 检测结果："
#                ss -tunlp | grep ":${i}" >> "${logDirPath}"
#                echo
#            fi
#            if [[ "${netstatExists}" -eq 1 ]]; then
#                echo "netstat 检测结果："
#                netstat -tunlp | grep ":${i}" >> "${logDirPath}"
#                echo
#            fi
#            if [[ "${lsofExists}" -eq 1 ]]; then
#                echo "lsof 检测结果："
#                lsof -i:"${i}" >> "${logDirPath}"
#                echo
#            fi
}

InnerOptionTemplate(){
    local innerOption=${1}
    local innerValue=${2}
    local innerVarName=${3}
    if [[ -z "${innerValue}" ]] || [[ "${innerValue}" =~ ^- ]]; then
        formatError "指定的选项 ${innerOption} 所对应的参数不能为空"
        formatError "以下是帮助菜单："
        InnerHelp
    else
        eval "${innerVarName}='${innerValue}'"
    fi
}

InputCheck(){
    formatInfo "正在检测输入的选项参数规范性..."
    local allArgs=("${@}") flag=0 ARGS
    getopt -a -o hi:l: -l help,ip:,log: -- "${allArgs[@]}" 2>/run/error-scan-port.tmp 1>/dev/null
    if [[ -f /run/error-scan-port.tmp ]]; then
        if [[ -n "$(cat /run/error-scan-port.tmp)" ]]; then
            errorOutput="$(cat /run/error-scan-port.tmp)"
            flag=1
        fi
        rm -rf /run/error-scan-port.tmp
    else
        formatError "选项读取异常，请检查，退出中"
        rm -rf /run/error-scan-port.tmp
        exit 1
    fi

    if [[ -n "${errorOutput}" ]]; then
        formatError "选项输入有误，报错信息："
        formatError "${errorOutput}"
        flag=1
        echo
    fi
    ARGS=$(getopt -a -o hi:l: -l help,ip:,log: -- "${allArgs[@]}" 2>/dev/null)
    eval set -- "${ARGS}"
    while true; do
        case "$1" in
        -l | --log)
            InnerOptionTemplate "${1}" "${2}" "logDirPath"
            shift 2
            ;;
        -i | --ip)
            InnerOptionTemplate "${1}" "${2}" "targetIP"
            shift 2
            ;;
        -h | --help)
            InnerHelp
            ;;
        --)
            shift
            ;;
        *)
            if [[ "${#@}" -ne 0 ]]; then
                formatError "禁止输入未指定选项的参数: ${*}"
                formatError "以下是帮助菜单："
                InnerHelp
            elif [[ "${#allArgs[@]}" -eq 0 ]]; then
                formatError "选项和对应参数不能为空"
                formatError "以下是帮助菜单："
                InnerHelp
            fi
            shift
            if [[ -z "${1}" ]]; then
                break
            fi
        esac
    done
    if [[ "${flag}" -ne 0 ]]; then
        formatError "以下是帮助菜单："
        InnerHelp
    else
        formatSuccess "输入的选项参数规范性检测通过"
    fi
}

TestRoot
IsClassifiedSystem
InputCheck "${@}"
ParseOption
TestDependence "${scanPlan}"
Scan "${scanPlan}"