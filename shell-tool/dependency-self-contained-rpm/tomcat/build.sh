#!/usr/bin/env bash
# 全局变量
tempProxyIP=
proxyIP=

buildEntryFilePath=
buildFolderPath=

latestNotify=
tomcatVer=
tomcatVersionNum=
tomcatAmount=
tomcatToolPath=
vendorEn=
vendorCn=
topDir=
specName=
tomcatUser=
javaHome=
offlineMode=
javaPackageName=
systemdLimitConf=
logRetentionPeriodType=
logRetentionPeriodAmount=

tomcatBinLink=
tomcatBinName=
tomcatFolderTemplateName=
tomcatSha=
tomcatShaLink=

# 默认以下目录文件已经准备好了（值为 0，即无须创建）：
# - 构建环境
# - spec 构建文件
envCreate=0
specCreate=0
folderStructure=("BUILD" "RPMS" "SOURCES" "SPECS" "SRPMS")

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

# 全局预处理
TestRoot() {
	if [ $EUID -eq 0 ] || [[ $(grep -o "^$(whoami):.*" /etc/passwd | cut -d':' -f3) = 0 ]]; then
        formatError "禁止使用 root 权限构建安装包，请切换非 root 用户再重新运行，退出中"
		exit 1
	fi
}

TestCurrentPath(){
    if [[ $0 =~ "/dev/fd" ]]; then
        formatError "此构建脚本禁止使用进程替换方式运行，退出中"
        exit 1
    fi
    buildEntryFilePath=$(readlink -f "$0")
    buildFolderPath=$(dirname "${buildEntryFilePath}")

    if [ ! -x "${buildEntryFilePath}" ]; then
        chmod +x "${buildEntryFilePath}"
    fi
}

TestDep(){
    formatInfo "正在检查构建环境依赖..."
    local i packageList=("wget" "curl" "coreutils" "rpmdevtools" "git" "make" "automake" "autoconf" "rpm-build" "rpmlint" "zip")
    local i flag rpmList
    rpmList=$(rpm -qa)
    flag=0
    for i in "${packageList[@]}"; do
        if ! echo -e "${rpmList}" | grep -E -o "^${i}-[0-9.]+.*" >/dev/null 2>&1; then
            formatErrorNoBlank "${i} 未安装"
            flag=1
        fi
    done
    if [[ "${flag}" -eq 1 ]]; then
        formatError "构建环境依赖检测失败，请按照以上报错自行安装依赖包，退出中"
        exit 1
    else
        formatSuccess "构建环境依赖检测通过"
    fi
}

ParseConfigFile(){
    formatInfo "正在查找并导入配置文件..."
    # 配置文件加载
    if [[ ! -f ${buildFolderPath}/config.ini ]]; then
        formatError "${buildFolderPath} 下未发现 config.ini 配置文件，即将生成配置模板并退出，请填写后再重新运行"
        ParseCreateIni
        formatWarningNoBlank "请自行修改此配置文件: "
        formatPrint "${buildFolderPath}/config.ini"
        exit 1
    elif [[ -f ${buildFolderPath}/config.ini ]]; then
        # shellcheck disable=SC2086
        if ! source ${buildFolderPath}/config.ini; then
            formatError "config.ini 配置文件导入存在错误，请检查键值对写法，比如：" "【键和等号】、【等号和值】之间不能有空格"
            formatError "退出中"
            exit 1
        else
            formatSuccess "配置文件成功导入"
        fi
    fi
}

ParseProxy(){
    formatInfo "正在检测代理配置..."
    if [[ "${SHELL}" =~ "bash" ]]; then
        :
    else
        formatWarning "当前 SHELL 环境未适配，跳过代理配置"
        return 0
    fi
    local proxyEnable flag
    proxyEnable=${proxy_enable}
    proxyIP=${proxy_ip}
    proxyPort=${proxy_port}
    unset proxy_enable
    unset proxy_ip
    unset proxy_port

    case "${proxyEnable}" in
    1)
        if [[ -z "${proxyIP}" ]]; then
            tempProxyIP="$(ip route show | grep -i default | awk '{ print $3}')"
            proxyIP="${tempProxyIP%.*}.1"
        elif [[ "${proxyIP}" == "localhost" ]] || [[ "${proxyIP}" == "127.0.0.1" ]]; then
            :
        elif [[ ! "${proxyIP}" =~ ^(([1-9]|[1-9][0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5]))\.(([1-9]?[0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5]))\.){2}([1-9]?[0-9]|1[0-9]{2}|2([0-4][0-9]|5[0-5])))$ ]]; then
            formatError "输入的 IP 地址不合法，请检查，退出中"
            exit 1
        fi

        if [[ -z "${proxyPort}" ]]; then
            proxyPort=7890
        elif [[ "${proxyPort}" -le 0 ]] || [[ "${proxyPort}" -gt 65535 ]]; then
            formatError "输入的端口不合法，请检查，退出中"
            exit 1
        fi

        if sp() {
            export https_proxy="http://${proxyIP}:${proxyPort}";\
            export http_proxy="http://${proxyIP}:${proxyPort}";\
            export all_proxy="socks5://${proxyIP}:${proxyPort}";\
            export ALL_PROXY="socks5://${proxyIP}:${proxyPort}";
        }; then
            flag=$((flag + 1))
        fi
        if usp() {
            unset https_proxy; \
            unset http_proxy; \
            unset all_proxy; \
            unset ALL_PROXY;
        }; then
            flag=$((flag + 1))
        fi
        if [[ "${flag}" -eq 2 ]]; then
            formatSuccess "代理配置完成，调用即代理"
        else
            formatError "代理配置无法使用，请检查"
            exit 1
        fi
        ;;
    0)
        # 这里不使用任何内建的代理方式，但当前ssh会话中已经启用的任何代理方式均不会受到影响
        if sp() {
            :
        }; then
            flag=$((flag + 1))
        fi
        if usp() {
            :
        }; then
            flag=$((flag + 1))
        fi
        if [[ "${flag}" -eq 2 ]]; then
            formatWarning "代理配置为空，调用即透传"
        else
            formatError "代理配置无法使用，请检查"
        fi
        :
        ;;
    *)
        formatError "proxy_enable 的值只能是 0 或 1，请重新输入，退出中"
        exit 1
    esac
}

ParseConfig(){
    formatInfo "正在解析配置文件..."
    # 批量驼峰映射
    tomcatVer=${tomcat_ver}
    tomcatVersionNum=${tomcat_version_num}
    tomcatAmount=${tomcat_amount}
    tomcatToolPath=${tomcat_tool_path}
    tomcatUser=${tomcat_user}
    vendorEn=${vendor_en}
    vendorCn=${vendor_cn}
    topDir=${topdir}
    specName=${spec_name}
    javaHome=${java_home}
    offlineMode=${offline_mode}
    logRetentionPeriodType=${log_retention_period_type}
    logRetentionPeriodAmount=${log_retention_period_amount}

#    # 老版本rpm构建工具不支持此类用法，暂时屏蔽功能
#    if declare -p java_package_name 2>/dev/null | grep -q 'declare \-a'; then
#        javaPackageName=$(sed -e 's/^/(/g' -e 's/$/)/g' -e 's/ / | /g' <<< "${java_package_name[*]}")
#    else
#        # shellcheck disable=SC2128
#        javaPackageName="${java_package_name}"
#    fi

    if declare -p systemd_limit_conf 2>/dev/null | grep -q 'declare \-a'; then
        systemdLimitConf=("${systemd_limit_conf[@]}")
    else
        formatError "systemd_limit_conf 的值必须是数组写法，禁止写字符串，请修改，退出中"
        exit 1
    fi
    unset tomcat_ver
    unset tomcat_version_num
    unset tomcat_amount
    unset tomcat_tool_path
    unset tomcat_user
    unset vendor_en
    unset vendor_cn
    unset topdir
    unset spec_name
    unset java_home
    unset java_package_name
    unset systemd_limit_conf
    unset log_retention_period_type
    unset log_retention_period_amount

    # 配置文件以下键必须有值
    # tomcat_version_num 在 tomcat_ver 不等于 latest 时可以为空
    # java_package_name 可以为空，创建 spec 文件时将跳过该选项
    if [ -z "${tomcatVer}" ] ||
    [ -z "${tomcatAmount}" ] ||
    [ -z "${tomcatToolPath}" ] ||
    [ -z "${tomcatUser}" ] ||
    [ -z "${vendorEn}" ] ||
    [ -z "${vendorCn}" ] ||
    [ -z "${topDir}" ] ||
    [ -z "${specName}" ] ||
    [ -z "${javaHome}" ] ||
    [ -z "${offlineMode}" ] ||
    [ "${#systemdLimitConf[@]}" -eq 0 ] ||
    [ -z "${logRetentionPeriodType}" ] ||
    [ -z "${logRetentionPeriodAmount}" ]; then
        formatError "存在部分键值为空，请检查，退出中"
        exit 1
    fi

    # tomcat 用户名
    if [[ "${tomcatUser}" =~ "-" ]]; then
        formatWarning "tomcat 用户名中包含特殊字符 '-'，在安装包构建完成时，安装包名中展示的用户名将使用下划线 '_' 代替 '-'"
        formatWarning "此内部替换仅影响到最终的安装包文件名，不影响到系统内创建的 tomcat 用户名"
        tomcatUserInPackageName=${tomcatUser//-/_}
    fi

    # 离线模式开关
    if [[ "${offlineMode}" -ne 0 ]] && [[ "${offlineMode}" -ne 1 ]]; then
        formatError "离线模式开关只能是 0 或 1，请检查，退出中"
        exit 1
    fi

    # tomcat 版本
    case ${tomcatVer} in
    "latest")
        if [[ "${offlineMode}" -eq 1 ]]; then
            formatError "离线模式下不支持获取最新版本信息，退出中"
            exit 1
        fi
        if [[ ! "${tomcatVersionNum}" =~ ^[0-9]+$ ]]; then
            formatError "tomcat大版本号必须为纯数字，退出中"
            exit 1
        fi
        latestNotify="(官网最新版)"
        if [[ "${tomcatVersionNum}" -lt 10 ]]; then
            local webNum firstFilter
            webNum="${tomcatVersionNum}0"
        else
            webNum="${tomcatVersionNum}"
        fi
        set -o pipefail
        sp
        if ! firstFilter=$(curl -fsSL https://tomcat.apache.org/download-"${webNum}".cgi); then
            formatError "tomcat最新版本信息获取失败，链接："
            formatError "https://tomcat.apache.org/download-${webNum}.cgi"
            formatError "请检查，退出中"
            exit 1
        fi
        tomcatVer=$(curl -fsSL https://tomcat.apache.org/download-"${webNum}".cgi | grep -E -o '>[0-9.]+</a>.*$' | awk -F '[><]' '{print $2}')
        tomcatShaLink=$(echo "${firstFilter}" | grep -E -o 'https://[a-z0-9:./-]+[0-9].tar.gz.*' | grep "sha512</a>" | awk -F '"' '{print $1}')
        tomcatBinLink=$(echo "${firstFilter}" | grep -E -o 'https://[a-z0-9:./-]+[0-9].tar.gz.*' | grep "tar.gz</a>" | awk -F '"' '{print $1}')
        tomcatBinName=$(echo "${tomcatBinLink}" | awk -F '/' '{print $NF}')
        tomcatFolderTemplateName="tomcat-${tomcatVersionNum}-template"
        if ! tomcatSha=$(curl -fsSL "${tomcatShaLink}"|awk '{print $1}'); then
            formatError "tomcat最新版本校验码获取失败，链接："
            formatError "${tomcatShaLink}"
            formatError "请检查，退出中"
            exit 1
        fi
        usp
        set +o pipefail
        ;;
    ''|*[0-9.]*)
        local parsedVersionNum
        parsedVersionNum=$(cut -d'.' -f1 <<< "${tomcatVer}")
        if [[ -z "${tomcatVersionNum}" ]]; then
            tomcatVersionNum="${parsedVersionNum}"
        elif [[ "${parsedVersionNum}" != "${tomcatVersionNum}" ]]; then
            formatError "配置文件中 tomcat_ver 对应的大版本号和 tomcat_version_num 的值不同"
            formatError "要么统一大版本号的值，要么将 tomcat_version_num 留空，退出中"
            exit 1
        fi
        if [[ ! "${tomcatVersionNum}" =~ ^[0-9]+$ ]]; then
            formatError "tomcat大版本号必须为纯数字，退出中"
            exit 1
        fi
        case "${offlineMode}" in
        0)
            set -o pipefail
            sp
            tomcatBinLink="https://archive.apache.org/dist/tomcat/tomcat-${tomcatVersionNum}/v${tomcatVer}/bin/apache-tomcat-${tomcatVer}.tar.gz"
            tomcatBinName=$(echo "${tomcatBinLink}"|awk -F '/' '{print $NF}')
            tomcatShaLink="https://archive.apache.org/dist/tomcat/tomcat-${tomcatVersionNum}/v${tomcatVer}/bin/apache-tomcat-${tomcatVer}.tar.gz.sha512"
            tomcatFolderTemplateName="tomcat-${tomcatVersionNum}-template"
            if ! tomcatSha=$(curl -fsSL "${tomcatShaLink}"|awk '{print $1}'); then
                formatError "tomcat最新版本校验码获取失败，请检查，退出中"
                exit 1
            fi
            set +o pipefail
            usp
            ;;
        1)
            # tomcat 官方包有固定名称格式，这里写死
            tomcatBinName="apache-tomcat-${tomcatVer}"
            if [[ ! -f "${buildFolderPath}/${tomcatBinName}.tar.gz" ]] && [[  ! -f "${buildFolderPath}/${tomcatBinName}.zip" ]]; then
                formatError "离线模式下未发现指定版本号的 tomcat 官方包:"
                formatErrorNoBlank "${buildFolderPath}/${tomcatBinName}.tar.gz" "${buildFolderPath}/${tomcatBinName}.zip"
                formatError "请重新下载，注意：官方包下载后请勿自行改名"
                exit 1
            elif [[ -f "${buildFolderPath}/${tomcatBinName}.tar.gz" ]]; then
                tomcatBinName="${tomcatBinName}.tar.gz"
            elif [[ -f "${buildFolderPath}/${tomcatBinName}.zip" ]]; then
                tomcatBinName="${tomcatBinName}.zip"
            fi
            tomcatFolderTemplateName="tomcat-${tomcatVersionNum}-template"
            tomcatBinLink="离线模式无此信息"
            tomcatShaLink="离线模式无此信息"
            tomcatSha="离线模式无此信息"
            ;;
        esac
        ;;
    *)
        formatError "配置文件中 tomcat_ver 的值只能是 latest 或 tomcat 真实版本号(数字开头，不带 v)，请检查，退出中"
        exit 1
    esac

    if [[ "${tomcatAmount}" -le 0 ]]; then
        formatError "tomcat本体数量必须是正整数，请修改配置文件，退出中"
        exit 1
    fi

    if [[ ! -f "${tomcatToolPath}" ]]; then
        formatError "配置文件中指定的 tomcat 辅助工具路径不存在，请检查，退出中"
        exit 1
    fi

    # 厂商信息无须解析直接使用

    # 构建路径
    if [[ ! -d "${topDir}" ]]; then
        envCreate=1
        specCreate=1
    else
        local i
        for i in "${folderStructure[@]}"; do
            if [[ ! -d "${topDir}/${i}" ]]; then
                envCreate=1
                break
            fi
        done
        if
        [[ ! -f ${topDir}/${tomcatFolderTemplateName}.sh ]] ||
        [[ ! -f ${topDir}/${tomcatBinName} ]] ||
        [[ ! -f "${topDir}/tomcat.${tomcatUser}.service" ]]; then
            envCreate=1
        fi
        if [[ ! -f "${topDir}/SPECS/${specName}" ]]; then
            specCreate=1
        fi
    fi


    # 非根目录且路径末尾有/则去掉路径末尾/
    if [[ ! ${tomcatToolPath} =~ ^/ ]]; then
        formatError "tomcat 辅助工具路径禁止使用相对路径，退出中"
        exit 1
    elif [[ ${tomcatToolPath} =~ /$ ]]; then
        formatError "tomcat 辅助工具路径是该文件的绝对路径，不是该文件所在目录的绝对路径，请修改，退出中"
        exit 1
    fi

    if [[ ! ${topDir} =~ ^/ ]]; then
        formatError "构建环境的根目录禁止使用相对路径，退出中"
        exit 1
    elif [[ ${topDir} =~ /$ ]]; then
        topDir="${topDir%/}"
    fi

    if [[ ! ${javaHome} =~ ^/ ]]; then
        formatError "java的安装路径禁止使用相对路径，退出中"
        exit 1
    elif [[ ${javaHome} =~ /$ ]]; then
        javaHome="${javaHome%/}"
    fi

    # 日志保留时长
    case "${logRetentionPeriodType}" in
    "day"|"week"|"month"|"year")
        case "${logRetentionPeriodType}" in
        "day")
            logRetentionPeriodType="daily"
            ;;
        "week")
            logRetentionPeriodType="weekly"
            ;;
        "month")
            logRetentionPeriodType="monthly"
            ;;
        "year")
            logRetentionPeriodType="yearly"
            ;;
        esac
        ;;
    *)
        formatError "配置文件中 log_retention_period_type 的值只能是 day week month year，请检查，退出中"
        exit 1
    esac

    if [[ "${logRetentionPeriodAmount}" -le 0 ]]; then
        formatError "log_retention_period_amount 的值必须是正整数，请修改配置文件，退出中"
        exit 1
    fi

    formatSuccess "配置文件解析完成"
}

ParseCreateIni(){
    cat > "${buildFolderPath}/config.ini" <<EOF
#----------------------------------
# 切换 tomcat 构建版本

## tomcat_ver
## tomcat 版本号
## 如果希望下载指定版本号的tomcat，则 tomcat_ver 的值必须和官网想要下载的真实 tomcat 二进制文件对应版本号完全相同
## 如果希望下载具体某个系列下的最新版本 tomcat，则 tomcat_ver 的值为 latest
## 如果设置 tomcat_ver 的值为 latest，则 tomcat_version_num 的值必须填写以决定下载哪个大版本号系列的最新版本 tomcat
## （不建议用任何大版本号系列中的老版本，大概率存在 CVE 漏洞导致等保评测过不了）
#tomcat_ver=latest
tomcat_ver=9.0.93

## tomcat_version_num
## tomcat 有多个系列大版本，大版本值是几，tomcat_version_num 的值就是几，比如：
## 9 系列版本号是 v9.xx.xx，那么 tomcat_version_num 的值就是 9
## 10 系列版本号是 v10.xx.xx，那么 tomcat_version_num 的值就是 10
## 如果是给 java8 使用的话无须修改，9 系列是 java8 支持的最后一个大版本系列
## 如果 tomcat_ver 的值非 latest，则此值可以留空，如果非空，则必须是具体指定的版本号对应的大版本号，例：
## tomcat_ver=9.0.91 对应 tomcat_version_num=9
## 注意：tomcat 打包没有适配 beta 版，不要用此套件为 beta 版本 tomcat 打包，会报错。
tomcat_version_num=9

## tomcat_amount
## tomcat 安装包中包含 tomcat 本体的数量
tomcat_amount=5

## tomcat_tool_path
## 定制的便于现场产品使用的tomcat辅助管理配置的脚本的绝对路径。
tomcat_tool_path=/home/build/test/tomcat-tool.sh

#----------------------------------
# 用户信息

## tomcat_user
## tomcat运行时所用用户名，本例中有两种 tomcat 的用户名，[root] 和 [非root] 用户，非root 用户名请自行定义，两种用户配置方式只能使用其中一种。
tomcat_user=tomcat-project
#tomcat_user=root

#----------------------------------
# 厂商信息

## vendor_en
## 厂商英文名，该名称会作为部署路径的一个文件夹名和包名的组成之一，假设名称为 <project>
## 注意：本打包套件制作出来的安装包，以上面参数为例，默认安装路径为: /opt/project。
## /opt 是个魔法值，因为各种国产软件均喜欢把非系统安装包装到 /opt 下自定义的一个文件夹中，麒麟和统信公司就是典型。
vendor_en=project

## vendor_cn
## 厂商中文名，该名称会出现在安装包的各种部署文件的中文详情中。假设名称为 <项目>
vendor_cn=项目

#----------------------------------
# 构建信息

## topdir
## 构建环境的根目录对应的绝对路径，例：/home/build/rpmbuild
topdir=/home/build/test/env

## spec_name
## rpm 打包专用的 spec 文件名，例：tomcat.spec
spec_name=tomcat.spec

#----------------------------------
# java 信息

## java_home
## java的安装路径，如果使用本配置文件的示例值，则java程序的绝对路径是: ${java_home}/bin/java
## 此路径必须是未来生产环境中所用的 JAVA_HOME，否则无法启动 tomcat
java_home=/opt/project/java-8

## java_package_name
## java的安装包名称，只出现在spec文件中，允许为空，即不指定必须安装某个包名的jre也能安装成功。
java_package_name=
#java_package_name=oracle-jdk8-project
#java_package_name=microsoft-jdk8-project

#----------------------------------
# systemd 资源限制信息

## systemd_limit_conf
## systemd 资源限制信息列表，只能用数组写法，无论是一种还是多种限制配置用，例：
## 多种配置：(LimitNOFILE=infinity TasksMax=infinity)
## 一种配置：(LimitNOFILE=infinity)
## 每个配置最好用双引号括起来，例："LimitNOFILE=infinity"，不括理论上可以，但有很小概率可能因为写法太非常规会解析异常。
## 更多参数请查看参考链接：
## https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Process%20Properties
## https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html#
#systemd_limit_conf=()
# systemd_limit_conf=(LimitNOFILE=infinity)
systemd_limit_conf=(LimitNOFILE=infinity TasksMax=infinity)

#----------------------------------
# clash 代理开关
## 因 tomcat 官网获取信息和下载文件对于国内网络来说连接不了或连接过慢，所以加了这个功能。
## 本套件只适配并测试了以下情况的虚拟机中走 clash 代理:
## - vmware workstation pro NAT和桥接
## - WSL2 默认 NAT
## 本配置实现类似 127.0.0.1:7890 且无账号密码的配置，非 clash 用户请自行修改对应端口号或提交其他软件的适配方案。

## proxy_enable
## 1 表示开启，即调用本构建套件内建代理功能
## 0 表示跳过本套件内建代理功能，即后续联网功能是否走代理与本套件无关
## 此构建套件运行时一定会走代理配置流程，但会根据 proxy_enable 的值来决定是否将代理流程配置置空，不会实际安装到系统环境变量中。
## 此值如果为 0，则后面 proxy_ip 和 proxy_port 无效
proxy_enable=1

## proxy_ip 和 proxy_port
## proxy_ip 默认值: 本工具自动检测虚拟机所在网络的转发 IP
## proxy_port 默认值: 7890，也就是 clash 默认的代理端口
## 二者任意一项被人工指定了值，则会覆盖默认值
##
## 如果是虚拟机的 NAT 联网，proxy_ip 可以为空
##
## 如果是【虚拟机的桥接】、【同网段实体机之间】、【本机】调用代理的方式：
## proxy_ip 必须指定安装代理软件的节点 IP
## 本机代理调用则使用 localhost 或 127.0.0.1
proxy_ip=
proxy_port=

#----------------------------------
# 离线模式开关
## offline_mode
## 1 表示开启离线模式
## 0 表示关闭离线模式
## 默认情况下此工具需要联网工作以自动完成下载、校验工作，但考虑到 tomcat 包下载存在的各种网络问题，增加了离线模式。
## 在离线模式下，本工具只会从本地文件夹中读取文件以完成环境准备。
## 因此需要用户自行完成 tomcat 包下载、校验完整性的操作，并将压缩包放到此配置文件所在的同级目录下，千万别改名
## 官网有 zip 和 tar.gz 两种压缩包，两种压缩包的处理离线模式均支持。

## 在线模式默认只下载 tar.gz 的压缩包到 topdir 选项所指定的绝对路径下（构建环境根目录），且一旦下载和校验完成后，会自动复制一份到此配置文件所在同级目录下，不会反向复制
## 之后重复构建的时候就可以启用离线模式跳过联网过程了。
## 注意：离线模式不支持 tomcat_ver 选项的值为 latest 的情况，必须手动指定具体版本号。
offline_mode=1

#----------------------------------
# 日志配置

## 日志保留时长
## log_retention_period_type
## 日志保留时长类型，默认为 weekly，可选值：day、week、month、year，必须小写。
log_retention_period_type=week

## log_retention_period_amount
## 日志保留的类型对应的数量，因 log_retention_period_type 值为 week
## 故此值以周数计数，日志过期时长为 4 周，即一个月的日志量，官方默认52周，即保留最近一年的日志。
log_retention_period_amount=4

EOF
}

HelpMain(){
    echo -e "
tomcat 半自动构建工具
可用选项:"
echo -e "
clean: 清理构建环境
check: 检查配置文件
build: 基于已有构建环境创建RPM包
help/h/-h/--help: 展示帮助
gen/generate: 生成配置文件
" | column -t

echo -e "
首次使用步骤(建议):
1. 执行此命令以自动生成配置文件: ${buildEntryFilePath}
2. 修改配置文件
3. 执行命令以确保构建环境完全干净: ${buildEntryFilePath} clean
4. 执行命令以完成构建环境基础组件的准备工作: ${buildEntryFilePath} gen env
5. 执行命令以完成构建规则配置文件的准备工作: ${buildEntryFilePath} gen spec
6. 执行命令以基于已有构建环境创建RPM包: ${buildEntryFilePath} build

其中第4、5步在首次确认没报错的情况下清空构建环境并重新生成时，可以用此命令代替:
${buildEntryFilePath} gen all

开发人员需要做的任何定制处理均需要在第4、5步之后，以及第6步之前完成。

如果完全搞坏了构建环境和构建流程规则，可以直接执行以下命令来重置:
${buildEntryFilePath} clean
${buildEntryFilePath} gen all

如果搞坏部分构建环境:
${buildEntryFilePath} gen env

如果搞坏部分构建流程规则:
${buildEntryFilePath} gen spec
"
}

HelpBuild(){
    echo -e "以下是可用的命令及对应功能:

构建安装包:
${buildEntryFilePath} build

查看此帮助菜单(功能一样，四选一):
${buildEntryFilePath} build help
${buildEntryFilePath} build h
${buildEntryFilePath} build -h
${buildEntryFilePath} build --help
"
}

HelpCheck(){
    echo -e "以下是可用的命令及对应功能:

检查配置文件解析情况:
${buildEntryFilePath} check

查看此帮助菜单(功能一样，四选一):
${buildEntryFilePath} check help
${buildEntryFilePath} check h
${buildEntryFilePath} check -h
${buildEntryFilePath} check --help
"
}

HelpGenerate(){
    echo -e "以下是可用的命令及对应功能:

一次性准备好或重置全部构建环境(功能一样，二选一):
${buildEntryFilePath} gen all
${buildEntryFilePath} generate all

只准备好或重置基本构建环境(功能一样，二选一):
${buildEntryFilePath} gen env
${buildEntryFilePath} generate env

只准备好或重置构建流程规则(功能一样，二选一):
${buildEntryFilePath} gen spec
${buildEntryFilePath} generate spec

查看此帮助菜单(功能一样，八选一):
${buildEntryFilePath} gen help
${buildEntryFilePath} gen h
${buildEntryFilePath} gen -h
${buildEntryFilePath} gen --help
${buildEntryFilePath} generate help
${buildEntryFilePath} generate h
${buildEntryFilePath} generate -h
${buildEntryFilePath} generate --help
"
}

HelpClean(){
    echo -e "以下是可用的命令及对应功能:

彻底清理配置文件中指定路径的构建环境:
${buildEntryFilePath} clean

查看此帮助菜单(功能一样，四选一):
${buildEntryFilePath} clean help
${buildEntryFilePath} clean h
${buildEntryFilePath} clean -h
${buildEntryFilePath} clean --help
"
}

# 以上是通用函数
# ---------------------------
# 以下是功能函数

CheckOptionRoute(){
    local optionList
    optionList=("$@")
    if [[ "${#optionList[@]}" -gt 1 ]]; then
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpBuild
        formatError "请重新指定，退出中"
        exit 1
    fi
    case ${optionList[0]} in
    "help"|"h"|"-h"|"--help")
        HelpCheck
        ;;
    "")
        CheckParse
        ;;
    *)
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpBuild
        formatError "请重新指定，退出中"
        exit 1
    esac


}

CheckParse(){
    formatWarningNoBlank "以下是解析结果汇总："
    local offlineModeInfo
    case "${offlineMode}" in
    0)
        offlineModeInfo="在线"
        ;;
    1)
        offlineModeInfo="离线"
        ;;
    esac

    echo -e "${CYAN}
本构建脚本的绝对路径: ${TAN}${buildEntryFilePath}${CYAN}
构建环境顶层路径: ${TAN}${topDir}${CYAN}
构建规则文件名: ${TAN}${specName}${CYAN}
工作模式: ${TAN}${offlineModeInfo}${NORM}
" | column -t
    echo -e "${CYAN}
tomcat版本号: ${TAN}${tomcatVer}${latestNotify}${CYAN}
tomcat系列版本号: ${TAN}${tomcatVersionNum}${CYAN}
tomcat包内包含的本体数量: ${TAN}${tomcatAmount}${CYAN}
tomcat运行用户: ${TAN}${tomcatUser}${CYAN}
tomcat辅助工具绝对路径: ${TAN}${tomcatToolPath}${CYAN}
tomcat二进制文件名: ${TAN}${tomcatBinName}${CYAN}
tomcat二进制下载地址: ${TAN}${tomcatBinLink}${CYAN}
tomcat二进制文件校验码下载链接: ${TAN}${tomcatShaLink}${CYAN}
tomcat二进制文件校验码: ${TAN}${tomcatSha}${CYAN}
" | column -t
    echo -e "${CYAN}
构建厂商英文名: ${TAN}${vendorEn}${CYAN}
构建厂商中文名: ${TAN}${vendorCn}${CYAN}
指定JAVA_HOME路径: ${TAN}${javaHome}${CYAN}
指定安装时依赖的JDK包名:" | column -t
    echo -e "${TAN}${javaPackageName}${NORM}"
    echo

    local tmpLimitList
    tmpLimitList=$(tr ' ' '\n' <<< "${systemdLimitConf[@]}")
    echo "${CYAN}systemd 资源限制配置列表: "
    echo -e "${TAN}${tmpLimitList}${NORM}"
    echo

    echo -e "${CYAN}内部代码:
env: ${TAN}${envCreate}${CYAN}
spec: ${TAN}${specCreate}${NORM}
" | column -t
    if [[ "${envCreate}" -eq 1 ]] || [[ "${specCreate}" -eq 1 ]]; then
        formatError "检测到构建目录结构或必须文件缺失，在正式构建前务必按照以下操作处理好构建前的准备工作："
    fi
    if [[ "${envCreate}" -eq 1 ]] && [[ "${specCreate}" -eq 1 ]]; then
        formatWarning "请执行以下命令创建、重置或修复构建所需的所有组件和结构："
        formatPrint "${buildEntryFilePath} gen all"
    else
        if [[ "${envCreate}" -eq 1 ]]; then
            formatWarning "指定的构建根路径和构建目录结构不存在或不完整，请执行以下命令创建或修复构建环境："
            formatPrint "${buildEntryFilePath} gen env"
        fi
        if [[ "${specCreate}" -eq 1 ]]; then
            formatWarning "指定的 spec 文件不存在，请执行以下命令创建 spec 文件："
            formatPrint "${buildEntryFilePath} gen spec"
        fi
    fi

    echo
    if [[ "${envCreate}" -eq 1 ]] || [[ "${specCreate}" -eq 1 ]] || [[ "${serviceCreate}" -eq 1 ]]; then
        formatError "退出中"
        exit 1
    fi
    unset offlineModeInfo
}

GenerateOptionRoute(){
    local optionList
    optionList=("$@")
    if [[ "${#optionList[@]}" -gt 1 ]]; then
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpGenerate
        formatError "请重新指定，退出中"
        exit 1
    fi
    case ${optionList[0]} in
    "all")
        GenerateEnv
        GenerateSpec
        ;;
    "env")
        GenerateEnv
        ;;
    "spec")
        if [[ "${envCreate}" -eq 1 ]]; then
            formatError "指定的构建根路径和构建目录结构不存在或不完整，请执行以下命令创建或修复构建环境："
            formatPrint "${buildEntryFilePath} gen env"
            formatError "退出中"
            exit 1
        fi
        GenerateSpec
        ;;
    "help"|"h"|"-h"|"--help")
        HelpGenerate
        ;;
    "")
        formatError "未输入参数，以下是帮助菜单:"
        HelpGenerate
        formatError "请重新指定，退出中"
        exit 1
        ;;
    *)
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpGenerate
        formatError "请重新指定，退出中"
        exit 1
    esac
}

GenerateEnv(){
    # 目录结构检测和创建
    formatInfo "正在检测构建环境目录结构和文件完整性..."
    if [[ "${envCreate}" -eq 0 ]]; then
        formatSuccess "构建环境目录结构和文件完整，跳过创建流程"
    else
        formatInfo "正在创建构建环境目录结构..."
        local i flag
        flag=0
        for i in "${folderStructure[@]}" ; do
            if ! mkdir -p "${topDir}/${i}"; then
                formatError "创建构建环境目录 ${topDir}/${i} 失败，请检查"
                flag=1
            fi
        done
        if [[ "${flag}" -eq 1 ]]; then
            formatError "构建环境目录结构存在错误，请检查，退出中"
            exit 1
        else
            formatSuccess "创建构建环境目录结构成功"
        fi
    fi

    # tomcat 辅助脚本
    formatInfo "正在复制 tomcat 辅助工具..."
    if [[ -f "${topDir}/${tomcatFolderTemplateName}.sh" ]]; then
        rm -rf "${topDir:?}/${tomcatFolderTemplateName}.sh"
    fi
    if ! cp -af "${tomcatToolPath}" "${topDir}/${tomcatFolderTemplateName}.sh"; then
        formatError "复制 tomcat 辅助工具失败，请自行检查，退出中"
        exit 1
    fi
        formatSuccess "tomcat 辅助工具复制成功"

    # tomcat 日志处理
    formatInfo "正在生成 tomcat 日志处理配置..."
    cat > "${topDir}/tomcat.${tomcatUser}.logrotate" <<EOF
$/opt/${vendorEn}/###TOMCAT_NAME###/logs/catalina*.log {
    copytruncate
    ${logRetentionPeriodType}
    rotate ${logRetentionPeriodAmount}
    compress
    missingok
    create 0644 ${tomcatUser} ${tomcatUser}
}
EOF
    formatSuccess "tomcat 日志处理配置生成完成"

    # tomcat systemd
    formatInfo "正在生成 systemd 服务配置文件..."
    cat > "${topDir}/tomcat.${tomcatUser}.service" <<EOF
[Unit]
Description=Tomcat-${tomcatVersionNum}-${vendorEn} ${vendorCn}定制版
After=syslog.target network.target

[Service]
SuccessExitStatus=143
Type=forking
User=${tomcatUser}
Environment=JAVA_HOME=${javaHome}
WorkingDirectory=/opt/${vendorEn}/###TOMCAT_NAME###
ExecStart=/opt/${vendorEn}/###TOMCAT_NAME###/bin/startup.sh
ExecStop=/opt/${vendorEn}/###TOMCAT_NAME###/bin/shutdown.sh
Restart=always

[Install]
WantedBy=default.target
EOF
    if [[ "${tomcatUser}" == "root" ]]; then
        if ! sed -i '/^User=/d' "${topDir}/tomcat.${tomcatUser}.service"; then
            formatError "systemd 服务配置文件 root 用户设置失败，请检查，退出中"
            exit 1
        fi
    fi
    if [[ "${#systemdLimitConf[@]}" -gt 0 ]]; then
        local tmpStr
        # shellcheck disable=SC2001
        tmpStr=$(sed 's/ /\\n/g' <<< "${systemdLimitConf[*]}")
        if sed -i "/^\[Service\]$/a\\${tmpStr}" "${topDir}/tomcat.${tomcatUser}.service"; then
            formatSuccess "systemd 服务配置文件生成成功"
        else
            formatError "systemd 资源限制选项插入失败，请检查，退出中"
            exit 1
        fi
    else
        formatSuccess "systemd 服务配置文件生成成功"
    fi

    # tomcat 本体下载和校验
    local flag=0
    case "${offlineMode}" in
    0)
        formatInfo "本工具工作模式为在线模式，正在检测 tomcat 二进制归档包..."
        local j shaResult shaBuildPath shaTopPath
        if [ -f "${buildFolderPath}/${tomcatBinName}" ] && [ -f "${topDir}/${tomcatBinName}" ]; then
            shaBuildPath=$(sha512sum "${buildFolderPath}/${tomcatBinName}" | cut -d' ' -f1)
            shaTopPath=$(sha512sum "${topDir}/${tomcatBinName}" | cut -d' ' -f1)
            if [[ "${shaBuildPath}" == "${shaTopPath}" ]]; then
                if [[ "${shaTopPath}" == "${tomcatSha}" ]]; then
                    formatSuccess "本地和构建环境均存在校验通过的 ${tomcatBinName} 归档包，将跳过下载"
                    flag=0
                else
                    formatWarning "本地和构建环境均存在校验不完整的 ${tomcatBinName} 归档包，将默认继续下载并在校验完成后完成替换"
                    flag=1
                fi
            elif [[ "${shaTopPath}" == "${tomcatSha}" ]]; then
                formatWarning "本地存在校验不完整的 ${tomcatBinName} 归档包，而构建环境归档包校验通过，将用构建环境归档包替换本地校验不完整的归档包"
                flag=0
                rm -rf "${buildFolderPath:?}/${tomcatBinName}"
                if ! cp "${topDir}/${tomcatBinName}" "${buildFolderPath}/${tomcatBinName}"; then
                    formatError "替换失败，请检查，退出中"
                    exit 1
                else
                    formatSuccess "本地归档包替换完成"
                fi
            elif [[ "${shaBuildPath}" == "${tomcatSha}" ]]; then
                formatWarning "本地存在校验通过的 ${tomcatBinName} 归档包，而构建环境归档包校验不完整，将用本地归档包替换构建环境校验不完整的归档包"
                flag=0
                rm -rf "${topDir:?}/${tomcatBinName}"
                if ! cp "${buildFolderPath}/${tomcatBinName}" "${topDir}/${tomcatBinName}"; then
                    formatError "替换失败，请检查，退出中"
                    exit 1
                else
                    formatSuccess "构建环境归档包替换完成"
                fi
            fi
        elif [ ! -f "${buildFolderPath}/${tomcatBinName}" ] && [ ! -f "${topDir}/${tomcatBinName}" ]; then
            formatWarning "本地和构建环境均不存在 ${tomcatBinName} 归档包，将默认下载、校验及备份"
            flag=1
        elif [ -f "${topDir}/${tomcatBinName}" ]; then
            shaTopPath=$(sha512sum "${topDir}/${tomcatBinName}" | cut -d' ' -f1)
            if [[ "${shaTopPath}" != "${tomcatSha}" ]]; then
                formatWarning "构建环境存在校验不完整的 ${tomcatBinName} 归档包，将默认继续下载并在校验完成后备份到本地"
                flag=1
            else
                formatSuccess "构建环境已存在版本为 v${tomcatVer} 且完整性校验通过的 ${tomcatBinName} 归档包，跳过下载流程"
                flag=0
                formatInfo "正在将构建环境的 tomcat 二进制归档包备份到本地..."
                if ! cp "${topDir}/${tomcatBinName}" "${buildFolderPath}"; then
                    formatError "备份 ${tomcatBinName} 归档包失败，请检查，退出中"
                    exit 1
                else
                    formatSuccess "备份 ${tomcatBinName} 归档包成功"
                fi
            fi
        elif [ -f "${buildFolderPath}/${tomcatBinName}" ]; then
            shaBuildPath=$(sha512sum "${buildFolderPath}/${tomcatBinName}" | cut -d' ' -f1)
            if [[ "${shaBuildPath}" != "${tomcatSha}" ]]; then
                formatWarning "本地存在校验不完整的 ${tomcatBinName} 归档包，将默认继续下载并在校验完成后备份到本地"
                flag=1
            else
                formatWarning "本地已存在版本为 v${tomcatVer} 且完整性校验通过的 ${tomcatBinName} 归档包，跳过下载流程"
                flag=0
                formatInfo "正在将本地的 tomcat 二进制归档包同步到构建环境根目录..."
                if ! cp "${buildFolderPath}/${tomcatBinName}" "${topDir}"; then
                    formatError "同步 ${tomcatBinName} 归档包失败，请检查，退出中"
                    exit 1
                else
                    formatSuccess "同步 ${tomcatBinName} 归档包成功"
                fi
            fi
        fi

        # 下载
        if [[ "${flag}" -eq 1 ]]; then
            for (( j = 1; j < 4; j++ )); do
                formatInfo "(${j}/3)正在下载 tomcat 二进制归档包..."
                if ! wget -c -P "${topDir}" "${tomcatBinLink}"; then
                    formatError "下载 ${tomcatBinName} 归档包失败，即将重试"
                    continue
                fi
                shaResult=$(sha512sum "${topDir}/${tomcatBinName}" | cut -d' ' -f1)
                if [[ ${tomcatSha} != "${shaResult}" ]]; then
                    formatWarning "本地 ${tomcatBinName} 归档包不完整且无法恢复，已清理下载残留"
                    rm -rf "${topDir:?}/${tomcatBinName}"
                else
                    formatSuccess "${tomcatBinName} 归档包下载并校验成功"
                    flag=0
                    break
                fi
            done
            
            case "${flag}" in
            0)
                formatInfo "正在将构建环境的 tomcat 二进制归档包备份到本地..."
                if [[ -f "${buildFolderPath}/${tomcatBinName}" ]]; then
                    rm -rf "${buildFolderPath:?}/${tomcatBinName}"
                fi
                if ! cp "${topDir}/${tomcatBinName}" "${buildFolderPath}"; then
                    formatError "备份 ${tomcatBinName} 归档包失败，请检查，退出中"
                    exit 1
                else
                    formatSuccess "备份 ${tomcatBinName} 归档包成功"
                fi
                ;;
            1)
                formatError "tomcat 下载或校验失败，请检查网络连接"
                formatError "因 tomcat 信息获取对中国大陆的网络连接性有一定需求，请自行配置代理"
                formatError "或者自行下载 ${tomcatBinName} 归档包到以下路径下，并重新运行脚本："
                formatPrint "${buildEntryFilePath}"
                formatError "退出中"
                exit 1
                ;;
            esac
        fi
        ;;
    1)
        formatInfo "本工具工作模式为离线模式，将跳过下载和校验流程，正在检测 tomcat 二进制归档包..."
        if [[ -f "${topDir}/${tomcatBinName}" ]]; then
            shaBuildPath=$(sha512sum "${buildFolderPath}/${tomcatBinName}" | cut -d' ' -f1)
            shaTopPath=$(sha512sum "${topDir}/${tomcatBinName}" | cut -d' ' -f1)
            if [[ "${shaBuildPath}" == "${shaTopPath}" ]]; then
                formatSuccess "本地和构建环境的 ${tomcatBinName} 归档包校验值相同，将跳过同步"
            else
                formatWarning "本地和构建环境的 ${tomcatBinName} 归档包校验值不同，将使用本地的 ${tomcatBinName} 归档包替换构建环境的同名归档包"
                rm -rf "${topDir:?}/${tomcatBinName}"
            fi
        fi

        if [[ ! -f "${topDir}/${tomcatBinName}" ]]; then
            if ! cp "${buildFolderPath}/${tomcatBinName}" "${topDir}"; then
                formatError "复制 ${tomcatBinName} 归档包失败，请检查，退出中"
                exit 1
            else
                formatSuccess "复制 ${tomcatBinName} 归档包成功"
            fi
        fi
        ;;
    esac

    # tomcat 解压
    formatInfo "正在解压并预调整 tomcat..."
    local decompressionProgram=() fileExtension
    if [[ "${tomcatBinName}" =~ .tar.gz$ ]]; then
        decompressionProgram=("tar" "xf")
        fileExtension=".tar.gz"
    elif [[ "${tomcatBinName}" =~ .zip$ ]]; then
        decompressionProgram=("unzip")
        fileExtension=".zip"
    fi
    pushd "${topDir}" >/dev/null 2>&1 || exit 2
    if [[ -d "${topDir}/${tomcatBinName//${fileExtension}/}" ]]; then
        rm -rf "${topDir:?}/${tomcatBinName//${fileExtension}/}"
        formatWarning "发现残留的原始 tomcat 已解压目录 ${tomcatBinName//${fileExtension}/}"
        formatWarning "已删除，请勿自行解压，如需对 tomcat 做任何调整，请直接执行命令:"
        formatPrint "${buildEntryFilePath} gen env"
    fi
    if ! "${decompressionProgram[@]}" "${topDir}/${tomcatBinName}"; then
        formatError "解压失败，请重新执行构建以自动检测校验或重新下载tomcat二进制归档包到 ${buildFolderPath}"
        formatError "退出中"
        exit 1
    fi
    popd >/dev/null 2>&1 || exit 3

    if [[ -d "${topDir}/${tomcatFolderTemplateName}" ]]; then
        rm -rf "${topDir:?}/${tomcatFolderTemplateName}"
        formatWarning "已删除发现的残留定制目录 ${topDir}/${tomcatFolderTemplateName}"
        formatWarning "在执行构建前，定制目录内可以自行做任何修改，构建时会直接用此目录构建安装包"
        formatWarning "本构建套件准备构建环境时会自动下载、解压归档包并重命名目录为: ${tomcatFolderTemplateName}"
        formatWarning "注意，在对 ${tomcatFolderTemplateName} 目录内容进行任何定制修改后，切勿再次执行以下命令生成构建环境，否则修改的任何内容都将会被重置:"
        formatPrint "${buildEntryFilePath} gen env"
    fi
    mv "${topDir}/${tomcatBinName//${fileExtension}/}" "${topDir}/${tomcatFolderTemplateName}"
    local currentBackupFolder currentBackupFolderPath currentParentBackupFolder
    currentBackupFolder="$(date +"%Y-%m-%d_%H-%M-%S")"
    currentParentBackupFolder="removed-file-backup"
    currentBackupFolderPath="${topDir}/${currentParentBackupFolder}/${currentBackupFolder}/${tomcatFolderTemplateName}"
    mkdir -p "${currentBackupFolderPath}"
    cp -r "${topDir}/${tomcatFolderTemplateName}/webapps/" "${currentBackupFolderPath}"
    cp -r "${topDir}/${tomcatFolderTemplateName}/logs/" "${currentBackupFolderPath}"
    cp -r "${topDir}/${tomcatFolderTemplateName}/work/" "${currentBackupFolderPath}"
    if [[ -d "${topDir}/${tomcatFolderTemplateName}/conf/Catalina" ]]; then
        cp -r "${topDir}/${tomcatFolderTemplateName}/conf/Catalina" "${currentBackupFolderPath}/conf"
    fi
    rm -rf "${topDir:?}/${tomcatFolderTemplateName}/webapps/"* \
    "${topDir:?}/${tomcatFolderTemplateName}/logs/"* \
    "${topDir:?}/${tomcatFolderTemplateName}/work/"* \
    "${topDir:?}/${tomcatFolderTemplateName}/conf/Catalina"
    mkdir -p "${topDir}/${tomcatFolderTemplateName}/webapps/ROOT"
    cat > "${topDir}/${tomcatFolderTemplateName}/webapps/ROOT/index.html" <<EOF
<html>
<head>
    <meta charset="UTF-8" />
</head>
<body>
    <h1>###TOMCAT_NAME### 启动成功，网络通畅</h1>
</body>
</html>
EOF
    formatSuccess "tomcat 解压并预调整完成，本次调整时删除的文件均备份在此目录下:"
    formatPrint "${currentBackupFolderPath}"

}

GenerateSpec(){
    formatInfo "正在生成 spec 文件..."
    cat > "${topDir}/SPECS/${specName}" <<EOF
%undefine _package_note_file
%global __check_files %{nil}
%global __os_install_post %{nil}
%global __arch_install_post %{nil}
%global _build_id_links none
%global debug_package %{nil}

# 外部传入的变量
%global tomcat_ver ${tomcatVer}
%global tomcat_version_num ${tomcatVersionNum}
%global vendor_en ${vendorEn}
%global vendor_cn ${vendorCn}
%global tomcat_user ${tomcatUser}
%global tomcat_user_in_package_name ${tomcatUserInPackageName}
%global java_package_name ${javaPackageName}
%global tomcat_folder_template_name ${tomcatFolderTemplateName}

# 全局变量
%global top_path /opt
%global tomcat_version_code tomcat-%{tomcat_version_num}
%global vendor_link https://github.com/mylovesaber/Tools-Share

Name:              tomcat-%{tomcat_version_num}-%{vendor_en}
Version:           %{tomcat_ver}
Release:           1%{?dist}.%{tomcat_user_in_package_name}
Summary:           tomcat-%{tomcat_user} %{vendor_cn}定制版
License:           GPLv3
URL:               %{vendor_link}
AutoReqProv:       no
BuildArch:         noarch
Requires:          %{java_package_name}
Requires(pre):     shadow-utils
BuildRequires:     systemd-rpm-macros

%description
此安装包为%{vendor_cn}项目部署所需的定制版 tomcat
该版本只能与包名为：%{java_package_name} 的定制版 JDK 搭配使用
此安装包安装后，不会对系统中已有的官方镜像源版本 tomcat 产生除运行端口号、配置文件中指定的各种路径以外的任何冲突

%prep

%build

%install
mkdir -p %{buildroot}/opt/%{vendor_en}
pushd %{buildroot}/opt/%{vendor_en}
###TOMCATBIN###
###TOMCATBINMOD###
popd

mkdir -p %{buildroot}%{_unitdir}
chmod 644 %{_topdir}/tomcat.%{tomcat_user}.service
pushd %{buildroot}%{_unitdir}
###TOMCATSERVICE###
###TOMCATSERVICEMOD###
popd

mkdir -p %{buildroot}%{_sysconfdir}/logrotate.d
chmod 644 %{_topdir}/tomcat.%{tomcat_user}.logrotate
pushd %{buildroot}%{_sysconfdir}/logrotate.d/
###TOMCATLOG###
###TOMCATLOGMOD###
popd

mkdir -p %{buildroot}%{_bindir}
chmod 755 %{_topdir}/%{tomcat_folder_template_name}.sh
pushd %{buildroot}%{_bindir}
###TOMCATTOOL###
###TOMCATTOOLNAME###
###TOMCATTOOLSERVICE###
popd

%pre
if [[ %{tomcat_user} != "root" ]]; then
    if ! getent group %{tomcat_user} > /dev/null; then
        %{_sbindir}/groupadd -f -r %{tomcat_user}
    fi
    if ! getent passwd %{tomcat_user} > /dev/null; then
        %{_sbindir}/useradd -r -g %{tomcat_user} -d %{top_path}/%{vendor_en}/.tomcat -s /sbin/nologin -c 'Tomcat %{vendor_cn}定制版' %{tomcat_user}
    fi
fi
if ! grep "vm.overcommit_memory" /etc/sysctl.conf >/dev/null 2>&1; then
    echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi

%post
###POST###

%preun
###PREUN###
%{__rm} -rf %{workdir}/* %{tempdir}/*

%postun
###POSTUN###

if [[ %{tomcat_user} != "root" ]]; then
        userdel %{tomcat_user} || :
        groupdel %{tomcat_user} || :
fi

%files
###FILELISTBEGIN###
###FILELISTEND###

# 日期转换方式：date +"%a %b %d %Y" -d "2023-10-14"
%changelog

EOF

    # 此处单独判断 java_package_name 是否为空，为空则要删除 spec 文件中的所有 java_package_name 部分
    if [[ -z "${javaPackageName}" ]]; then
        sed -i '/java_package_name/d' "${topDir}/SPECS/${specName}"
    fi
    # 多个tomcat
    local i \
    \
    tomcatBinList=() \
    tomcatBinModList=() \
    \
    tomcatServiceList=() \
    tomcatServiceModList=() \
    \
    tomcatLogList=() \
    tomcatLogModList=() \
    \
    tomcatToolList=() \
    tomcatToolPathList=() \
    tomcatToolServiceList=() \
    \
    postServiceList=() \
    preUnServiceList=() \
    postUnServiceList=() \
    \
    installTomcatBinPathList=() \
    installTomcatServicePathList=() \
    installTomcatToolPathList=() \
    installTomcatLogPathList=()

    for (( i = 1; i <= tomcatAmount; i++ )); do
        mapfile -t -O "${#tomcatBinList[@]}" tomcatBinList < <(echo "    cp -rp %{_topdir}/${tomcatFolderTemplateName} tomcat-${tomcatVersionNum}-${i}")
        mapfile -t -O "${#tomcatBinModList[@]}" tomcatBinModList < <(echo "    sed -i 's/###TOMCAT_NAME###/tomcat-${tomcatVersionNum}-${i}/g' tomcat-${tomcatVersionNum}-${i}/webapps/ROOT/index.html")

        mapfile -t -O "${#tomcatServiceList[@]}" tomcatServiceList < <(echo "    cp %{_topdir}/tomcat.%{tomcat_user}.service %{name}-${i}.service")
        mapfile -t -O "${#tomcatServiceModList[@]}" tomcatServiceModList < <(echo "    sed -i 's/###TOMCAT_NAME###/tomcat-%{tomcat_version_num}-${i}/g' %{name}-${i}.service")

        mapfile -t -O "${#tomcatLogList[@]}" tomcatLogList < <(echo "    cp %{_topdir}/tomcat.%{tomcat_user}.logrotate %{name}-${i}.%{tomcat_user}")
        mapfile -t -O "${#tomcatLogModList[@]}" tomcatLogModList < <(echo "    sed -i 's/###TOMCAT_NAME###/tomcat-%{tomcat_version_num}-${i}/g' %{name}-${i}.%{tomcat_user}")

        mapfile -t -O "${#tomcatToolList[@]}" tomcatToolList < <(echo "    cp -p %{_topdir}/${tomcatFolderTemplateName}.sh tomcat-%{tomcat_version_num}-${i}")
        mapfile -t -O "${#tomcatToolPathList[@]}" tomcatToolPathList < <(echo "    sed -i 's|###TOMCAT_PATH###|%{top_path}/%{vendor_en}/tomcat-%{tomcat_version_num}-${i}|g' tomcat-%{tomcat_version_num}-${i}")
        mapfile -t -O "${#tomcatToolServiceList[@]}" tomcatToolServiceList < <(echo "    sed -i 's|###TOMCAT_SERVICE###|%{name}-${i}.service|g' tomcat-%{tomcat_version_num}-${i}")

        mapfile -t -O "${#postServiceList[@]}" postServiceList < <(echo "%systemd_post %{name}-${i}.service")
        mapfile -t -O "${#preUnServiceList[@]}" preUnServiceList < <(echo "%systemd_preun %{name}-${i}.service")
        mapfile -t -O "${#postUnServiceList[@]}" postUnServiceList < <(echo "%systemd_postun_with_restart %{name}-${i}.service")

        mapfile -t -O "${#installTomcatBinPathList[@]}" installTomcatBinPathList < <(echo "%{top_path}/%{vendor_en}/tomcat-%{tomcat_version_num}-${i}")
        mapfile -t -O "${#installTomcatServicePathList[@]}" installTomcatServicePathList < <(echo "%attr(0644,root,root) %{_unitdir}/%{name}-${i}.service")
        mapfile -t -O "${#installTomcatToolPathList[@]}" installTomcatToolPathList < <(echo "%attr(755, root, root) %{_bindir}/tomcat-%{tomcat_version_num}-${i}")
        mapfile -t -O "${#installTomcatLogPathList[@]}" installTomcatLogPathList < <(echo "%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/logrotate.d/%{name}-${i}.%{tomcat_user}")
    done

# 这里是原版tomcat的权限记录备份，没有全用上
#cat >> /dev/null << EOF
#%global basedir %{_var}/lib/%{name}
#%global appdir %{basedir}/webapps
#%global homedir %{_datadir}/%{name}
#%global bindir %{homedir}/bin
#%global confdir %{_sysconfdir}/%{name}
#%global libdir %{_javadir}/%{name}
#%global logdir %{_var}/log/%{name}
#%global cachedir %{_var}/cache/%{name}
#%global tempdir %{cachedir}/temp
#%global workdir %{cachedir}/work
#%global _systemddir /lib/systemd/system
#
#
#%attr(0755,root,tomcat) %dir %{basedir}
#%attr(0755,root,tomcat) %dir %{confdir}
#
#%defattr(0664,tomcat,root,0770)
#%attr(0770,tomcat,root) %dir %{logdir}
#
#%defattr(0664,root,tomcat,0770)
#%attr(0770,root,tomcat) %dir %{cachedir}
#%attr(0770,root,tomcat) %dir %{tempdir}
#%attr(0770,root,tomcat) %dir %{workdir}
#
#%defattr(0644,root,tomcat,0775)
#%attr(0775,root,tomcat) %dir %{appdir}
#%attr(0775,root,tomcat) %dir %{confdir}/Catalina
#%attr(0775,root,tomcat) %dir %{confdir}/Catalina/localhost
#%config(noreplace) %{confdir}/*.policy
#%config(noreplace) %{confdir}/*.properties
#%config(noreplace) %{confdir}/context.xml
#%config(noreplace) %{confdir}/server.xml
#%attr(0640,root,tomcat) %config(noreplace) %{confdir}/tomcat-users.xml
#%attr(0664,root,tomcat) %{confdir}/tomcat-users.xsd
#%attr(0664,root,tomcat) %config(noreplace) %{confdir}/jaspic-providers.xml
#%attr(0664,root,tomcat) %{confdir}/jaspic-providers.xsd
#%config(noreplace) %{confdir}/web.xml
#
#%files webapps
#%defattr(0644,tomcat,tomcat,0755)
#%{appdir}/ROOT
#EOF


    # tomcatBinList
    # tomcatBinModList
    ###TOMCATBIN###
    ###TOMCATBINMOD###
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatBinList[*]}")
    if ! sed -i "/^###TOMCATBIN###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATBIN###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatBinModList[*]}")
    if ! sed -i "/^###TOMCATBINMOD###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATBINMOD###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr

    # tomcatServiceList
    # tomcatServiceModList
    ###TOMCATSERVICE###
    ###TOMCATSERVICEMOD###
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatServiceList[*]}")
    if ! sed -i "/^###TOMCATSERVICE###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATSERVICE###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatServiceModList[*]}")
    if ! sed -i "/^###TOMCATSERVICEMOD###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATSERVICEMOD###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr

    # tomcatLogList=()
    # tomcatLogModList=()
    ###TOMCATLOG###
    ###TOMCATLOGMOD###
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatLogList[*]}")
    if ! sed -i "/^###TOMCATLOG###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATLOG###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatLogModList[*]}")
    if ! sed -i "/^###TOMCATLOGMOD###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATLOGMOD###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr

    # tomcatToolList
    # tomcatToolPathList
    # tomcatToolServiceList
    ###TOMCATTOOL###
    ###TOMCATTOOLNAME###
    ###TOMCATTOOLSERVICE###
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatToolList[*]}")
    if ! sed -i "/^###TOMCATTOOL###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATTOOL###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatToolPathList[*]}")
    if ! sed -i "/^###TOMCATTOOLNAME###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATTOOLNAME###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed 's/     /\\n    /g' <<< "${tomcatToolServiceList[*]}")
    if ! sed -i "/^###TOMCATTOOLSERVICE###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###TOMCATTOOLSERVICE###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr

    # postServiceList
    # preUnServiceList
    # postUnServiceList
    ###POST###
    ###PREUN###
    ###POSTUN###
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed -e 's/%systemd_post/\\n%systemd_post/g;s/^\\n//g' <<< "${postServiceList[*]}")
    if ! sed -i "/^###POST###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###POST###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed -e 's/%systemd_preun/\\n%systemd_preun/g;s/^\\n//g' <<< "${preUnServiceList[*]}")
    if ! sed -i "/^###PREUN###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###PREUN###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr=$(sed -e 's/%systemd_postun_with_restart/\\n%systemd_postun_with_restart/g;s/^\\n//g' <<< "${postUnServiceList[*]}")
    if ! sed -i "/^###POSTUN###$/a\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###POSTUN###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr

    # installTomcatBinPathList
    # installTomcatServicePathList
    # installTomcatToolPathList
    # installTomcatLogPathList
    ###FILELISTBEGIN###
    ###FILELISTEND###
    if ! sed -i "/^###FILELISTBEGIN###$/a\\%defattr(-, %{tomcat_user}, %{tomcat_user}, -)" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###FILELISTBEGIN_HEADER###"
        formatError "请检查，退出中"
        exit 1
    fi

    local tmpStr
    # shellcheck disable=SC2001
    tmpStr="$(sed -e 's/%{top_path}/\\n%{top_path}/g;s/^\\n//g' <<< "${installTomcatBinPathList[@]}")"
    if ! sed -i "/^###FILELISTEND###$/i\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###FILELISTBEGIN_BIN###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr="$(sed -e 's/%attr/\\n%attr/g;s/^\\n//g' <<< "${installTomcatServicePathList[@]}")"
    if ! sed -i "/^###FILELISTEND###$/i\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###FILELISTBEGIN_SERVICE###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr="$(sed -e 's/%attr/\\n%attr/g;s/^\\n//g' <<< "${installTomcatToolPathList[@]}")"
    if ! sed -i "/^###FILELISTEND###$/i\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###FILELISTBEGIN_TOOL###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr
    local tmpStr
    # shellcheck disable=SC2001
    tmpStr="$(sed -e 's/%attr/\\n%attr/g;s/^\\n//g' <<< "${installTomcatLogPathList[@]}")"
    if ! sed -i "/^###FILELISTEND###$/i\\${tmpStr}" "${topDir}/SPECS/${specName}"; then
        formatError "定制 spec 文件生成失败，错误信息: ###FILELISTBEGIN_LOGROTATE###"
        formatError "请检查，退出中"
        exit 1
    fi
    unset tmpStr

    # 删除定位标记
    if sed \
        -e '/^###TOMCATBIN###/d' \
        -e '/^###TOMCATBINMOD###/d' \
        -e '/^###TOMCATSERVICE###/d' \
        -e '/^###TOMCATSERVICEMOD###/d' \
        -e '/^###TOMCATLOG###/d' \
        -e '/^###TOMCATLOGMOD###/d' \
        -e '/^###TOMCATTOOL###/d' \
        -e '/^###TOMCATTOOLNAME###/d' \
        -e '/^###TOMCATTOOLSERVICE###/d' \
        -e '/^###POST###/d' \
        -e '/^###PREUN###/d' \
        -e '/^###POSTUN###/d' \
        -e '/^###FILELISTBEGIN###/d' \
        -e '/^###FILELISTEND###/d' -i \
    "${topDir}/SPECS/${specName}"; then
        formatSuccess "spec 文件生成成功"
    else
        formatError "单个 tomcat 定制 spec 文件生成失败，请检查，退出中"
        exit 1
    fi
}

BuildOptionRoute(){
    local optionList
    optionList=("$@")
    if [[ "${#optionList[@]}" -gt 1 ]]; then
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpBuild
        formatError "请重新指定，退出中"
        exit 1
    fi
    case ${optionList[0]} in
    "help"|"h"|"-h"|"--help")
        HelpBuild
        ;;
    "")
        if [[ "${envCreate}" == "0" ]] && [[ "${specCreate}" == "0" ]]; then
            BuildPackage
        elif [[ "${envCreate}" == "0" ]] && [[ "${specCreate}" == "1" ]]; then
            formatError "构建安装包的准备工作不完善，请执行此命令以完善:"
            formatErrorNoBlank "${buildEntryFilePath} gen spec"
            formatError "退出中"
            exit 1
        elif [[ "${envCreate}" == "1" ]] && [[ "${specCreate}" == "0" ]]; then
            formatError "构建安装包的准备工作不完善，请执行此命令以完善:"
            formatErrorNoBlank "${buildEntryFilePath} gen env"
            formatError "退出中"
            exit 1
        elif [[ "${envCreate}" == "1" ]] && [[ "${specCreate}" == "1" ]]; then
            formatError "请执行此命令以完整创建构建安装包前的准备工作:"
            formatErrorNoBlank "${buildEntryFilePath} gen all"
            formatError "退出中"
            exit 1
        fi
        ;;
    *)
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpBuild
        formatError "请重新指定，退出中"
        exit 1
    esac
}

BuildPackage(){
    formatInfo "正在基于已有构建环境创建 RPM 包..."
    if ! rpmbuild -D "_topdir ${topDir}" -bb "${topDir}/SPECS/${specName}"; then
        formatError "构建失败，请重建 spec 文件或检查配置文件是否有不合适的配置，退出中"
        exit 1
    else
        formatSuccess "tomcat 安装包构建成功！" "生成的 RPM 安装包在此目录下: "
        echo "${topDir}/RPMS/noarch"
    fi
}

CleanOptionRoute(){
    local optionList
    optionList=("$@")
    if [[ "${#optionList[@]}" -gt 1 ]]; then
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpClean
        formatError "请重新指定，退出中"
        exit 1
    fi
    case ${optionList[0]} in
    "help"|"h"|"-h"|"--help")
        HelpClean
        ;;
    "")
        CleanEnv
        ;;
    *)
        formatError "输入参数不合法，以下是帮助菜单:"
        HelpClean
        formatError "请重新指定，退出中"
        exit 1
    esac
}

CleanEnv(){
    formatInfo "正在清理构建环境..."
    rm -rf "${topDir}"
    formatSuccess "构建环境清理成功，如需重新构建，请先执行以下命令完成创建安装包所需的构建环境:"
    echo "${buildEntryFilePath} gen all"
}

TestRoot
TestCurrentPath
TestDep
ParseConfigFile
ParseProxy
ParseConfig

firstOption="${1}"
extraArgs=("${@:2}")
case "${firstOption}" in
    "clean")
        CleanOptionRoute "${extraArgs[@]}"
        ;;
    "check")
        CheckOptionRoute "${extraArgs[@]}"
        ;;
    "build")
        BuildOptionRoute "${extraArgs[@]}"
        ;;
    "gen"|"generate")
        GenerateOptionRoute "${extraArgs[@]}"
        ;;
    "help"|"h"|"-h"|"--help")
        if [[ "${#extraArgs[@]}" -gt 0 ]]; then
            formatError "展示帮助菜单的选项之后禁止添加任何其他内容，请重新指定，退出中"
            HelpMain
            exit 1
        else
            HelpMain
        fi
    ;;
    *)
        formatError "未输入参数或参数输入错误！可选项: clean/check/build/[gen|generate]"
        formatError "退出中"
esac
