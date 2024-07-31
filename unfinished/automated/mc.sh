#!/usr/bin/env bash
# version: v1.0.1
# 全局颜色定义(适配涉密机)
isClassified=0
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
IsClassifiedSystem

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

# 全局预处理
CheckRoot() {
	if [ $EUID != 0 ] || [[ $(grep -o "^$(whoami):.*" /etc/passwd | cut -d':' -f3) != 0 ]]; then
        formatError "没有 root 权限！"
        formatError "请运行 \"sudo su -\" 命令并重新运行该脚本"
		exit 1
	fi
}

mcPath=
entryPath=
GetCurrentPath(){
    if [[ $0 =~ "/dev/fd" ]]; then
        formatError "此工具禁止使用进程替换方式运行，退出中"
        exit 1
    fi
    mcPath=$(readlink -f "$0")
    entryPath=$(dirname "${mcPath}")

    if [ ! -x "${mcPath}" ]; then
        chmod +x "${mcPath}"
    fi
}

# 全局方法，使用全局变量mainOperationName进行路由，各级定义数组下标即可打印全部错误参数列表
InvalidParam(){
    local invalidArgs=("${extraArgs[@]:$1}")
    formatError "请删除无效的参数后重新运行：${invalidArgs[*]}"
    formatError "如果不知道如何使用，请查看帮助菜单"
    OperationHelp
}

# 全局方法，使用全局变量mainOperationName进行路由，各级方法只需调此函数名即可完成对应操作调用
OperationHelp(){
    formatInfoNoBlank "以下是帮助菜单："
    case "${mainOperationName}" in
        "main")
            MainHelp
        ;;
        "start")
            StartHelp
        ;;
        "stop")
            StopHelp
        ;;
        "restart")
            RestartHelp
        ;;
        "list")
            RestartHelp
        ;;
        "check")
            CheckHelp
        ;;
    esac
    exit 1
}

formatInfo "正在初始化工作环境"
if
CheckRoot
GetCurrentPath;then
    cd "${entryPath}" || exit 1 # 整套脚本的统一入口，内部都是相对路径
    formatSuccess "工作环境初始化完成"
fi
extraArgs=("${@:2}")
source ./flow/Help.sh

# 配置文件解析
# 因 shell 语法限制，为了通用性设置多个数组配合：
# groupNameList 组名列表，为有序一维数组，存放服务组名信息用于索引
# groupAndServiceChain 组名和服务名串联列表，为有序一维数组，存放所有组名和对应的服务名，先添加组名为新元素，然后将该组所有服务名依次添加为新元素
# groupAndServiceIndexPair 组名和服务名对应数组下标配对，为无序关联数组，键为组名，groupAndServiceChain 中组名后面跟着的对应所有服务的起始和末尾服务名对应的下标值，两个值通过符号连接为一个字符串作为值
# serviceAndCommandPair 服务名和命令配对，为无序关联数组，键为服务名，值为对应服务的执行命令
# excludeServiceList 排除列表，为有序一维数组，元素只有服务名没有组名
# allServiceList 全部可控服务列表，为有序一维数组，元素只有服务名没有组名
excludeServiceList=()
groupNameList=()
groupAndServiceChain=()
allServiceList=()
declare -gA groupAndServiceIndexPair serviceAndCommandPair
source ./flow/parser/Parse.sh
## 测试数组组装情况
#for key in "${!groupAndServiceIndexPair[@]}"; do
#    value="${groupAndServiceIndexPair[$key]}"
#    echo "Key: $key, Value: $value"
#done
#echo "排除列表：${excludeServiceList[*]}"
#echo "组名列表：${groupNameList[*]}"
#echo "组名和服务名列表：${groupAndServiceChain[*]}"
#
#for key1 in "${!serviceAndCommandPair[@]}"; do
#    value="${serviceAndCommandPair[$key1]}"
#    echo "Key: $key1, Value: $value"
#    IFS=' ' read -r -a my_array <<< "$value"
#    echo "${#my_array[@]}"
#done
#exit 0
# 控制流程
# index是收集有错参数的数组下标传递给InvalidParam函数的
index=
mainOperationName="${1}"
case "${mainOperationName}" in
"check")
    source ./flow/operation/CheckOperation.sh
    ;;
"list")
    source ./flow/operation/ListOperation.sh
    ;;
"start"|"stop"|"restart")
    source ./flow/operation/StartStopOperation.sh
    ;;
"" | "h" | "help" | "-h" | "--help")
    if [ -z "${extraArgs[0]}" ]; then
        MainHelp
    else
        index=0
        mainOperationName="main"
        InvalidParam ${index}
    fi
    ;;
*)
    index=0
    extraArgs=("$@")
    mainOperationName="main"
    InvalidParam "${index}"
    ;;
esac
