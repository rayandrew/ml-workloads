#!/bin/bash

CMD="flux jobs --format=\"{id.f58:>12} ?:{queue:<8.8} +:{username:<8} {name:<20.20+} {nnodes:>6h} {status_abbrev:>2.2} {contextual_time!F:>8h} {contextual_info}\""

#  {ntasks:>6} {nnodes:>6h} {contextual_time!F:>8h}

watch -n2 "$CMD"