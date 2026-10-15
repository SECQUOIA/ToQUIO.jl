#!/usr/bin/env python3
"""Plot verified tables; never dispatch a solver or sampler."""
import argparse, csv, json, platform
import importlib.metadata as metadata
from collections import defaultdict
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ARMS=('native','radix4','bounded4-cap64','binary-radix2','toqubo-controlled-binary','toqubo-default-binary')
COLORS=dict(zip(ARMS,plt.rcParams['axes.prop_cycle'].by_key()['color']))
MARKERS=dict(zip(ARMS,('o','s','^','v','x','+')))

def rows(path):
    with open(path,newline='') as source: return list(csv.DictReader(source))

def produce(directory):
    structural=rows(directory/'structural.csv'); batches=rows(directory/'knapsack-batches.csv')
    for family in ('facility','inventory','route_allocation','knapsack'):
        profiles=sorted({r['profile'] for r in structural if r['family']==family})
        for profile in profiles:
            groups=[None]+sorted({int(r['m']) for r in structural if r['family']==family and r['profile']==profile})
            for selected_m in groups:
                fig,axes=plt.subplots(1,2,figsize=(12,4.8),constrained_layout=True)
                for arm in ARMS:
                    selected=[r for r in structural if r['family']==family and r['profile']==profile and
                              r['arm']==arm and r['status']=='measured' and
                              (selected_m is None or int(r['m'])==selected_m)]
                    for ax,key in zip(axes,('density','active_variables')):
                        usable=[r for r in selected if r.get(key,'') not in ('','undefined')]
                        ax.scatter([int(r['n']) for r in usable],[float(r[key]) for r in usable],
                                   s=16,alpha=.55,color=COLORS[arm],marker=MARKERS[arm],label=arm)
                axes[0].set(ylabel='Canonical graph density',xlabel='First source dimension n',ylim=(-.02,1.02))
                axes[1].set(ylabel='Active target variables',xlabel='First source dimension n')
                if family=='facility': axes[1].set_yscale('log')
                for ax in axes:ax.grid(alpha=.2)
                handles,labels=axes[0].get_legend_handles_labels()
                fig.legend(handles,labels,loc='outside lower center',ncol=3,fontsize=8)
                group='all second dimensions' if selected_m is None else f'm/s={selected_m}'
                description='One manufactured validation fixture' if profile=='manufactured' else 'Three fresh draws'
                fig.suptitle(f'{family}: {profile}; {group}\n{description}; descriptive observations')
                fig.savefig(directory/(f'{family}-{profile}-structure'+('' if selected_m is None else f'-m{selected_m}')+'.png'),dpi=160);plt.close(fig)
    for replicate in (None,1,2,3):
        fig,axes=plt.subplots(1,2,figsize=(12,4.8),constrained_layout=True)
        for arm in ARMS:
            selected=[r for r in batches if r['arm']==arm and
                      (replicate is None or int(r['replicate'])==replicate)]
            usable=[r for r in selected if r['sense_aware_terminal_relative_gap']]
            axes[0].scatter([int(r['n'])+.015*(int(r['m'])-10) for r in usable],
                [float(r['sense_aware_terminal_relative_gap']) for r in usable],s=18,alpha=.5,color=COLORS[arm],marker=MARKERS[arm],label=arm)
            axes[1].scatter([int(r['n'])+.015*(int(r['m'])-10) for r in selected if r['terminal_feasible_frequency']],
                [float(r['terminal_feasible_frequency']) for r in selected if r['terminal_feasible_frequency']],s=18,alpha=.5,color=COLORS[arm],marker=MARKERS[arm])
        axes[0].set(xlabel='Items n (small m jitter)',ylabel='Sense-aware gap to direct reference')
        axes[1].set(xlabel='Items n (small m jitter)',ylabel='Feasible / observed terminal reads',ylim=(-.02,1.02))
        for ax in axes:ax.grid(alpha=.2)
        handles,labels=axes[0].get_legend_handles_labels();fig.legend(handles,labels,loc='outside lower center',ncol=3,fontsize=8)
        name='pooled' if replicate is None else f'replicate-{replicate}'
        fig.suptitle(f'Local knapsack sampling: {name}\nThree batches; uncertified references remain incumbent-relative')
        fig.savefig(directory/f'knapsack-quality-{name}.png',dpi=160);plt.close(fig)
    for replicate in (1,2,3):
        fig,axes=plt.subplots(1,2,figsize=(12,4.8),constrained_layout=True)
        for arm in ARMS:
            selected=[r for r in batches if r['arm']==arm and int(r['replicate'])==replicate]
            hits=[r for r in selected if r['median_first_feasible_seconds_conditional_on_hit']]
            axes[0].scatter([int(r['n']) for r in hits],
                [float(r['median_first_feasible_seconds_conditional_on_hit']) for r in hits],s=18,alpha=.5,color=COLORS[arm],marker=MARKERS[arm],label=arm)
            axes[1].scatter([int(r['n']) for r in selected],
                [int(r['no_hit_censored_chains'])/10 for r in selected],s=18,alpha=.5,color=COLORS[arm],marker=MARKERS[arm])
        axes[0].set(xlabel='Items n',ylabel='Median first feasible seconds, conditional on a hit')
        axes[1].set(xlabel='Items n',ylabel='No-hit censored chains / 10 planned chains',ylim=(-.02,1.02))
        for ax in axes:ax.grid(alpha=.2)
        handles,labels=axes[0].get_legend_handles_labels();fig.legend(handles,labels,loc='outside lower center',ncol=3,fontsize=8)
        fig.suptitle(f'Observed first source feasibility: replicate {replicate}\nLocal software; no IID time-to-success estimate')
        fig.savefig(directory/f'knapsack-feasibility-time-replicate-{replicate}.png',dpi=160);plt.close(fig)
    (directory/'plot-environment.json').write_text(json.dumps(dict(python=platform.python_version(),matplotlib=matplotlib.__version__,
        packages={d.metadata['Name']:d.version for d in metadata.distributions()}),sort_keys=True)+'\n')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('report',type=Path)
    produce(parser.parse_args().report)
