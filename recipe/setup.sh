#!/usr/bin/bash


if [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
    echo "$0 usage: ./$0 [-h|--help] [--hzzExtras] [-j NTHREADS]"
    echo "    --hzzExtras: Get and compile HZZ matrix element and kinematic fit stuff, and generate the UWVV plugins that use them."
    echo "               This is not the default because most people do not need them and one of the packages' authors frequently make changes that break everything without intervention on our side."
    echo "               NB if you use this option and later use scram b clean, you should rerun this script with this option or your CONDOR jobs may fail."
    echo "    --met: Download updated MET correction recipes (needed for MET filters and uncertainties)"
    echo "    -j NTHREADS: [with --hzzExtras] Compile ZZMatrixElement package with NTHREADS threads (default 12)."
    exit 1
fi

while [ "$1" ]
do
    case "$1" in
        --hzzExtras)
            HZZ=1
            ;;
        --met)
            MET=1
            ;;
        -j)
            shift
            UWVVNTHREADS="$1"
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac

    shift
done

if [ ! "$UWVVNTHREADS" ]; then
    UWVVNTHREADS=12
fi

pushd $CMSSW_BASE/src

#https://twiki.cern.ch/twiki/bin/view/CMS/EgammaPostRecoRecipes#2018_Data_MC
git cms-merge-topic cms-egamma:EgammaPostRecoTools #just adds in an extra file to have a setup function to make things easier
#From CMSSW_10_2_10, our ID PR has been merged so it is no longer necessary to do "git cms-merge-topic cms-egamma:EgammaID_1023". If you work in CMSSW < 10_2_10, 
#then you have to merge that PR still
scram b -j 8
git clone git@github.com:cms-egamma/EgammaAnalysis-ElectronTools.git EgammaAnalysis/ElectronTools/data
cd EgammaAnalysis/ElectronTools/data
git checkout ScalesSmearing2018_Dev
cd -
git cms-merge-topic cms-egamma:EgammaPostRecoTools_dev
scram b -j 8
##Note this assumes you havnt checked out the EgammaAnalysis/ElectronTools package in CMSSW which is likely. 
##If you do need this checked out for some reason, just copy the Run2018_Step2Closure_CoarseEtaR9Gain_*.dat files to 
##EgammaAnalysis/ElectronTools/data/ScalesSmearings manually.


####################Not used at the moment
if [ "$HZZ" ]; then

    if [ ! -d ./ZZMatrixElement ]; then
        echo -e "\nSetting up ZZ matrix element stuff"
        git clone https://github.com/cms-analysis/HiggsAnalysis-ZZMatrixElement.git ZZMatrixElement

        pushd ZZMatrixElement
        git checkout -b from-v205 v2.0.5

        # Fix their bullshit.
        # We have to authenticate to the CERN server the MCFM library is stored on with a cookie
        # If something is going wrong with ZZMatrixElement stuff, it's probably
        # related to this.
        MCFM_URL=`cat MELA/data/"$SCRAM_ARCH"/download.url`
        # Make cookie
        env -i KRB5CCNAME="$KRB5CCNAME" cern-get-sso-cookie -u "$MCFM_URL" -o MELA/data/"$SCRAM_ARCH"/cookie.txt --krb -r
        if [ ! -e MELA/data/retrieveBkp.csh ]; then
            # Backup the library retrieve script if necessary
            cp MELA/data/retrieve.csh MELA/data/retrieveBkp.csh
        fi
        # Edit their wget command to use the cookie
        sed 's/wget/wget --load-cookies=cookie.txt/' MELA/data/retrieveBkp.csh > MELA/data/retrieve.csh

        # They download the library during their build process.
        # And with our fix, they actually get it instead of the html for the
        # CERN login page...
        source setup.sh -j "$UWVVNTHREADS"
        popd
    fi

    # copy libraries dowloaded by MELA to lib so they get packaged and used by CONDOR
    cp ZZMatrixElement/MELA/data/"$SCRAM_ARCH"/*.so "$CMSSW_BASE"/lib/"$SCRAM_ARCH"

    if [ ! -d ./KinZfitter ]; then
        echo -e "\nSetting up Z kinematic fit stuff"
        git clone https://github.com/VBF-HZZ/KinZfitter.git
    fi

    # generate UWVV's MELA plugin
    cp UWVV/AnalysisTools/plugins/ZZDiscriminantEmbedderCode.txt UWVV/AnalysisTools/plugins/ZZDiscriminantEmbedder.cc
    cp UWVV/AnalysisTools/plugins/ZKinematicFitEmbedderCode.txt UWVV/AnalysisTools/plugins/ZKinematicFitEmbedder.cc
fi
####################Not used at the moment


if [ ! -d ./KaMuCa ]; then
    echo "Setting up muon calibration"
    git clone https://github.com/bachtis/analysis.git -b KaMuCa_V4 KaMuCa
fi

popd
