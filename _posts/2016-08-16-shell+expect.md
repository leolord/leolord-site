---
layout: post
title: shell+expect 前端一键部署脚本
category: 前端
excerpt: 前端代码的部署，通常只是将编译打包好的文件**复制**到远程服务器上的一个目录。 对于七牛之类的CDN服务，其实也是相同的原理，不过CDN的部署有更便捷的方式，这里不做讨论，只说前者的部署方式。不过你有没有觉得每次都打开一个ftp客户端，鼠标一下下点击到你要部署的目录，然后把文件拖进去，这样的操作比神烦狗还烦呢？
tags: 开发 部署 shell expect
---

前端代码的部署，通常只是将编译打包好的文件**复制**到远程服务器上的一个目录。 对于七牛之类的CDN服务，其实也是相同的原理，不过CDN的部署有更便捷的方式，这里不做讨论，只说前者的部署方式。不过你有没有觉得每次都打开一个ftp客户端，鼠标一下下点击到你要部署的目录，然后把文件拖进去，这样的操作比神烦狗还烦呢？

另外一个问题是，每次部署的环境可能不同： 有时候，是为了远程调试接口； 有时候，是为了测试；有时候是为了上线前的预发环境验证；还有时候，额。。那就是正式上线了。（有没有觉得这句话很像小学课文）

针对不同环境的部署，我们需要打不同的包，部署到不同的机器上，或者”机器群“。这些问题，下面一一化解。


### 针对不同环境打包
---

我所在的公司使用高大上的**Webpack**进行打包（其实是巨慢无比，没有tree shaking功能的复杂构建工具），而Webpack可以通过[EnvironmentPlugin](http://webpack.github.io/docs/list-of-plugins.html#environmentplugin)来区分不同的环境。具体执行起来，可以分为三步：

#### 1. 在webpack的配置文件中配置EnvironmentPlugin

*直到写这篇博客的时候才发现，我这里用的是DefinePlugin，不过差不多，不要在意这些细节*

对于不同的环境，其实要使用不同的webpack配置脚本，这里只以打包部署的时候用到的配置脚本为例，代码如下:

```js
{
    entry: ...
    output: ...
    module: ...
    plugins: {
        ...
        new webpack.EnvironmentPlugin([
            "NODE_ENV"
        ])
        ...
    }
}
```

添加了上面的配置，在脚本中就可以用`var env = process.env.NODE_ENV`来访问打包时候的环境变量了。 我仿佛已经看到了做NodeJS同学的鄙视脸： ”还用这么费劲，我们直接访问就行了“。

#### 2. 在代码中针对不同的环境变量进行配置

其实也就是一个`switch`的事情，代码如下：

```js
var env = process.env.NODE_ENV
var ajaxRoot // 我这里通常需要配置的是后端接口的路径

switch (env) {
  case 'test':
    ajaxRoot = '测试环境的接口路径'
    break
  case 'pre':
    ajaxRoot='预发环境的接口路径'
    break
  default:
    ajaxRoot='线上环境的接口路径'
}
```

#### 3. 编译打包

在编译打包的时候，可以直接指定环境变量：

```sh
NODE_ENV=test && webpack  --config 你的配置脚本
```

当然`NODE_ENV`也是常用的环境变量名，其实什么名字都无所谓啦~~

### 部署脚本
---

开篇就说了部署也不过是一个拷贝文件的过程，你是不是觉得这样很简单？ 其实还是有坑的。  
比如：

  1. 网速不好，一部分文件更新了，一部分没有怎么办？
  1. 我们的服务器故意将ssh的免密登陆关闭了，只用shell脚本的话，没完没了的输入密码，是不是很烦？

下面是我们的解法

#### expect简介

`expect`可以说是*nix环境下的键盘自动输入工具，这个命令通常在`/usr/bin/expect`，它是一个系统自带命令，不需要单独安装。  
它其实是一个简单的解释器，解释一段expect脚本； 它使用tcl语法（这个鬼东西我没兴趣研究，但是貌似很有用）。  
其脚本的通常格式是

> spawn xx命令
> expect xx输出
> send xx命令
> expect disconnect 或者interactive （断开expect和shell的链接，或者将shell的交互转交给用户）

上面第二行，`expect xx`就是第一行创建的任务的输出期待，如果希望产生的输出出现了，就继续执行下面的命令，上面例子中是继续向shell发送指令。这里我总觉的是简单的输入输出重定向，不知道是不是这样。

#### 部署脚本

那么既然expect可以代替我们每次手动敲密码，那简单的部署脚本就出来了，下面是我正在用的：

```sh
#!/usr/bin/expect

set timeout 30 # 命令超时时间，单位是秒
set host 远程机器
set username 服务器的用户名
set passwd 服务器的密码
set tarname 要拷贝的tar包名字
set target_dir [lindex $argv 0] # 从命令行读取第一个参数作为目标目录


spawn scp $tarname $username@$host:$target_dir # 将打包好的tar包拷贝到远程服务器，至于spawn这个单词，想想NodeJS里面的那个spawn

expect {
  "*yes/no*" {send "yes\r"} # 第一次连接远程服务器的时候，ssh会提示原先没有连接过这个服务器，是否信任它的公钥（yue 四声）， 这里出现这个yes/no的提示，就发送一个yes
  "*assword*" {send "$passwd\r"} # 如果不是第一次连接，那么通常ssh会提示输入密码，那输入就好咯~
}

expect eof # 这句我很怀疑是否需要，它是期望上面的scp命令接收到一个end-of-file，或者说scp的输出结束标识

spawn ssh $username@$host # 之后ssh到远程服务器，将刚才上传的tar包解压

expect {
  "*yes/no*" {send "yes\r"} # 由于上面已经发送了yes了，所以这句是废话，不过我不希望下面的代码块依赖上面的代码块，方便我需要的时候直接删除某一部分，这里就重复下呗，又不死人
  "*assword*" {send "$passwd\r"}
}

expect "$" # 这行很蛋疼，因为不同的shell使用的命令提示符号不同，所以原先我写`expect "#"`，换台机器有可能会卡死，后来就改成'$'了，意思是行尾
send "mkdir -p $target_dir\r" # 创建需要部署目录的路径，是不是觉得这个执行顺序不对？ 是的，就是不对，应该先创建目录再scp，我就是懒得改，咋地？
expect "$" 
send "cd $target_dir\r" # 进入目标目录
expect "$"
send "tar xzf $tarname\r" # 解压，我通常用'tar.gz'格式的压缩包，如果你希望网络传输更小一点，可以用'tar.bz2'的，或者7zip的，看心情啦~
expect "$"
send "exit\r" # 退出shell登录
expect disconnect # 退出expect和shell的链接，我不确定这行是否需要，原先没这行也没啥问题

```

你会注意到，我并没有直接scp一个目录，而是scp一个压缩包，这样就可以避免文件上传失败导致页面只更新了一部分的问题。当然真实情况中，只上传了一半的tar包也可能解压出一些东西来，导致部署失败。那你就加一个md5校验呗，反正我这里很少遇到这种情况，所以就懒得理了。

#### 分环境打包并部署的脚本

到这里还没完，你应该发现这个expect脚本还需要接收一个参数，每次敲`/usr/bin/expect deploy.tcl 目标路径`也挺烦的，所以还需要最终将打包和部署结合到一起的另外一个shell脚本:

```sh
#!/bin/bash

# 下面这三个变量是shell中指定颜变的变量值，我真的很烦shell里面这点，看下我们consle.log对于样式的支持，多么友好
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

case $1 in
  dev)  env=dev-remote
        target=远程联调环境的部署路径
        ;;
  test) env=testing
        target=测试环境的部署路径
        ;;
  pre)  env=pre
        target=预发环境的部署路径
        ;;
  production)    env=production
        target=生产环境的部署路径
        ;;
  *)    echo '必须指定部署环境'
        exit
esac

echo -e "打包环境为${RED}${env}${NC}, 部署目录为${RED}${target}${NC}"

read -p "确认打包并部署吗? " -n 1 -r 
echo    # 换行
if [[ ! $REPLY =~ ^[Yy]$ ]] # $REPLY是用户按下的第一个按键，所以输入`Y/y/yes`，或者输入法的候选词都会跳过这个分支，继续下面的脚本
then
    exit
fi

echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"
echo -e "${YELLOW}   开始打包${NC}"
echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"

export NODE_ENV=${env}
npm run build # 这里开始编译

(
  cd dist || exit
  tar czf 压缩包的名字.tar.gz ./*
) # 我管这个叫打包😄，虽然明显不是通常所说的webpack的打包

echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"
echo -e "${YELLOW}   开始部署${NC}"
echo -e "${YELLOW}--------------------------------------------------------------------------------${NC}"

/usr/bin/expect ./deploy.tcl $target
```

#### 和npm结合下

这一步纯属多余，但是在一个基于NodeJS的一套前端脚手架中使用expect或者shell都是有点怪怪的，所以把运行shell命令的部分放到了package.json里面的scripts部分：

```json
{
    "deploy:test": "deploy.sh test",
    "deploy:dev": "deploy.sh dev",
    "deploy:pre": "deploy.sh pre",
    "deploy:production": "deploy.sh production"
}
```

现在每次部署的时候，只需要`npm run deploy:dev/test/pre/production`就行了，看上去很像是那么一回事了。鉴于我的英语水平实在是渣渣，敲production这个单词很很难敲对，所以很难出现一不小心将开发中的代码部署到线上的问题。

### 其他闲扯
---

上面的脚本基本够我用，也只是基本够用而已。 一个很明显的坑就是创建目标目录的时机不对。其实我真实的做法是在scp那里，现将tar.gz文件复制到`$HOME`目录下。 只不过我们的运维工程师起初并没有为每个开发人员单独创建用户，所以我就偷懒了。

另外一个问题是，如果需要部署到多台远程机器呢？ 还是很好办（我在撒谎，我对shell编程不熟悉，在处理二维数组的时候吭哧老半天），在打包并部署的那个脚本里面改下就行了：

```sh
...
case $1 in
  test)  env=test
        export PRESET_1=('第一台机器的ip' '第一台机器的部署路径')
        export PRESET_2=('第二台机器的ip' '第二台机器的部署路径')
        count=2
        ;;
...
esac

...

for ((i=1; i<=count; ++i)); do
  var="PRESET_${i}[@]" #动态变量，我写这段脚本的时候才知道，原来shell根本不支持二维数组/元祖
  set "${!var}" # 将上面的变量当做当前命令行的参数，反正我是这么理解的，要不下面的$1 $2啥的我就看不懂了
  ./deploy.tcl "$1" "$2" "$tarname" #改下上面的那个tcl脚本，让它接收三个参数，我这里偷懒了，直接将deploy.tcl设置成了可执行文件
done
```

### 归根结底
---

最最正确的方法，应该是将工程和部署脚本分离，工程中应该只放代码和编译代码需要的文件，工程应当和要部署到的环境相互透明才对。 但是谁让咱们公司小嘞，没啥条件。

我理解的真正一键部署，应该是用CI。比较知名的CI工具就是jenkins，但是jenkens真的很不灵活。反正我觉得那玩意儿不够灵活，尤其在远程联调程序阶段，需要部署的既不是某个常规branch（我指的是master/develop），也不是某个tag，而是根据本次开发任务确认的一个feature/***的分支。 在配置jenkins的时候，我们的运维工程师表示，每次开新需求都配置下，我心中一万个那个啥奔腾而过。

另外一条路就是gitlab自带的CI支持，不过那个需要一台单独的服务器，或者一个运行环境在远程运行打包部署过程，这个机器可以配置很非常低，只要足够稳定。在打包之前还可以运行eslint/单元测试/e2e测试等等。 但，我们还是输给了**穷**。


穷是原罪啊~~    By: 完蛋大人
